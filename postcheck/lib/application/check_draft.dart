import 'dart:async';
import 'package:postcheck_rules/contracts.dart';
import '../domain/models.dart';
import '../domain/ports.dart';
import 'ocr_merge.dart';
import 'ai_contract.dart';

final class CheckDraft {
  const CheckDraft({
    required this.perception,
    required this.context,
    this.perceptionBudget = const Duration(seconds: 45),
    this.contextBudget = const Duration(seconds: 90),
  });
  final PerceptionPort perception;
  final ContextAnalysisPort context;
  final Duration perceptionBudget, contextBudget;

  Future<CheckReport> call(
    DraftInput draft, {
    List<String> privateWords = const [],
    PublishedVenue? venue,
    void Function(String)? onProgress,
    void Function()? onCanFinish,
    bool Function()? isCancelled,
    bool Function()? finishRequested,
  }) async {
    final watch = Stopwatch()..start();
    final notes = <String>[];
    var observations = const Observations();
    var stopPerception = false;
    bool cancelled() => isCancelled?.call() ?? false;
    bool finishing() => finishRequested?.call() ?? false;
    onProgress?.call('写真の文字と人物を確認しています');
    if (draft.photo != null) {
      final pending = _StageWait<Observations>(
        perceptionBudget,
        cancelled,
        finishing,
      );
      final progressive = perception is ProgressivePerceptionPort
          ? perception as ProgressivePerceptionPort
          : null;
      try {
        final work = progressive == null
            ? perception.inspect(draft.photo!)
            : progressive.inspectProgressively(
                draft.photo!,
                budget: perceptionBudget,
                shouldStop: () => stopPerception || cancelled() || finishing(),
                onPartial: (partial, basicComplete) {
                  if (stopPerception || cancelled() || finishing()) return;
                  observations = partial;
                  if (basicComplete) {
                    pending.shorten(progressive.additionalBudget);
                    onCanFinish?.call();
                  }
                },
                onProgress: (message) {
                  if (!stopPerception && !cancelled() && !finishing()) {
                    onProgress?.call(message);
                  }
                },
              );
        observations = await pending.wait(work);
      } on _StageStopped catch (e) {
        if (e.reason == 'cancelled') throw StateError('cancelled');
        notes.add(
          e.reason == 'finish'
              ? '追加の確認を終了しました。取得済みの結果を表示しています。'
              : '写真の解析を途中で終了しました。取得済みの結果を表示しています。目視でも確認してください。',
        );
      } catch (_) {
        if (cancelled()) rethrow;
        notes.add('写真の解析を一部実行できませんでした。取得済みの結果と文章のチェックを表示しています。');
      } finally {
        stopPerception = true;
        pending.dispose();
      }
    }
    if (cancelled()) throw StateError('cancelled');
    final checker = RuleChecker(privateWords: privateWords, venue: venue);
    final findings = checker.check(draft, observations);
    // Prioritize actionable OCR groups without changing full basic-rule coverage.
    final priorities = {
      for (final f in findings)
        if (f.targetKey != null &&
            (f.kind == FindingKind.contact ||
                f.kind == FindingKind.privateWord))
          f.targetKey!.substring(4),
    };
    final aiBlocks = [...observations.blocks]
      ..sort((a, b) {
        final priority =
            (priorities.contains(b.id) ? 1 : 0) -
            (priorities.contains(a.id) ? 1 : 0);
        if (priority != 0) return priority;
        final y = a.region.y.compareTo(b.region.y);
        return y != 0 ? y : a.region.x.compareTo(b.region.x);
      });
    final aiObservations = Observations(
      blocks: aiBlocks,
      faces: observations.faces,
      devices: observations.devices,
      notes: observations.notes,
    );
    final aiInput = buildContextInput(draft, aiObservations, venue: venue);
    onCanFinish?.call();
    onProgress?.call('文章と写真の確認候補を整理しています');
    ContextResult ai;
    if (finishing() ||
        (perception is ProgressivePerceptionPort &&
            (perception as ProgressivePerceptionPort).isRunning)) {
      ai = const ContextResult(status: '追加のAI確認を省略しました。基本チェックの結果を表示しています。');
    } else {
      final pending = _StageWait<ContextResult>(
        contextBudget,
        cancelled,
        finishing,
      );
      try {
        ai = await pending.wait(
          context.analyze(
            draft,
            aiObservations,
            venue: venue?.policy.validAt(DateTime.now()) == true ? venue : null,
          ),
        );
      } catch (_) {
        ai = const ContextResult(status: 'AIの確認が完了しませんでした。基本チェックの結果を表示しています。');
      } finally {
        pending.dispose();
      }
    }
    if (cancelled()) throw StateError('cancelled');
    return CheckReport(
      findings: mergeReviewFindings([...findings, ...ai.findings]),
      notes: [
        if (venue != null)
          '${venue.policy.name} / v${venue.version}：${venue.policy.validAt(DateTime.now())
              ? venue.policy.hasLegacyRuleDetails
                    ? '施設ルールを適用しています。適用エリア・撮影日時は原文と照合してください。'
                    : '施設が指定した確認項目を適用しています。'
              : '有効期限が過ぎています。施設ルールは未確認です。'}',
        if (venue != null &&
            venue.policy.hasLegacyRuleDetails &&
            venue.policy.publication != RulePermission.allowed)
          '施設のSNS公開条件：${venue.policy.publication.label}。写真の修正だけでは公開条件を満たすとは限りません。',
        ...{...observations.notes, ...notes},
        if (venue != null &&
            venue.policy.validAt(DateTime.now()) &&
            venue.policy.hasLegacyRuleDetails &&
            draft.caption.trim().isNotEmpty)
          if (aiInput.venueRule == null)
            venue.policy.sourceText.trim().isEmpty
                ? '施設ルールの原文がないため、投稿文との意味の照合は未実施です。施設の案内を確認してください。'
                : '施設ルールが長いため、投稿文との意味の照合は未実施です。条件・例外を省略せず原文で確認してください。'
          else if (!ai.venueReviewCompleted)
            '施設ルールの文章と投稿文の意味の照合は完了していません。基本チェックとは別に、原文も確認してください。'
          else
            '施設ルールの文章と投稿文を端末内AIで照合しました。見落としの可能性があります。適用条件・掲載許可は確認してください。',
        if (aiInput.omitted)
          'AIに渡せる長さを超えるため、一部の文章・画像内の文字は文脈確認の対象外です。基本チェックは全体が対象です。',
      ],
      aiStatus: ai.status,
      elapsed: watch.elapsed,
      completedAt: DateTime.now(),
    );
  }
}

final class _StageStopped implements Exception {
  const _StageStopped(this.reason);
  final String reason;
}

/// Keeps handlers on the losing future, so late native errors cannot leak.
final class _StageWait<T> {
  _StageWait(Duration budget, this.cancelled, this.finishing) {
    _deadline = Timer(budget, () => _stop('timeout'));
    _poll = Timer.periodic(const Duration(milliseconds: 25), (_) {
      if (cancelled()) {
        _stop('cancelled');
      } else if (finishing()) {
        _stop('finish');
      }
    });
  }
  final bool Function() cancelled, finishing;
  final _interrupted = Completer<T>();
  Timer? _deadline, _extra, _poll;
  void _stop(String reason) {
    if (!_interrupted.isCompleted) {
      _interrupted.completeError(_StageStopped(reason));
    }
  }

  void shorten(Duration budget) {
    _extra ??= Timer(budget, () => _stop('timeout'));
  }

  Future<T> wait(Future<T> work) => Future.any([work, _interrupted.future]);
  void dispose() {
    _deadline?.cancel();
    _extra?.cancel();
    _poll?.cancel();
  }
}

final class RuleChecker {
  const RuleChecker({this.privateWords = const [], this.venue});
  final List<String> privateWords;
  final PublishedVenue? venue;
  List<String> get activeVenueWords =>
      venue?.policy.activeWords(DateTime.now()) ?? const [];
  String? evidenceFor(String text) =>
      activeVenueWords.any((w) => text.toLowerCase().contains(w.toLowerCase()))
      ? '${venue!.policy.name} / v${venue!.version}\n${venue!.policy.sourceText}'
      : null;
  static final _email = RegExp(
    r'[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}',
    caseSensitive: false,
  );
  static final _phone = RegExp(
    r'(?<![\w])(?:\+[1-9](?:[ .()\-]*[0-9]){6,14}|0\d{1,4}[ -]?\d{1,4}[ -]?\d{3,4})(?!\d)',
  );
  static final _future = RegExp(
    r'未公開|未発表|解禁|来月|来週|近日|新企画|新商品|リリース予定|発表予定|\b(?:confidential|not yet announced|under embargo|unreleased|upcoming launch)\b',
    caseSensitive: false,
  );

  List<Finding> check(DraftInput draft, Observations observations) {
    final found = <Finding>[];
    for (final (index, device) in observations.devices.indexed) {
      found.add(
        Finding(
          id: 'device-$index',
          kind: FindingKind.screenDevice,
          question: switch (device.detectionLabel) {
            'whiteboard' => 'ホワイトボードが写っています。隠しますか？',
            'wine_glass' => 'お酒（ワイングラス）が写っています。隠しますか？',
            'book' => '本・資料が写っています。隠しますか？',
            'picture_frame' => '額縁が写っています。隠しますか？',
            'poster' => 'ポスターが写っています。隠しますか？',
            _ =>
              device.outline == null
                  ? 'パソコンやスマホが写っています。隠しますか？'
                  : '画面の輪郭候補を確認してください。隠しますか？',
          },
          target: PhotoTarget(device.padded(.012)),
          source: FindingSource.deviceModel,
          detectedLabel: device.detectionLabel,
        ),
      );
    }
    for (final (index, face) in observations.faces.indexed) {
      found.add(
        Finding(
          id: 'face-$index',
          kind: FindingKind.face,
          question: '写っている方の掲載許可は確認済みですか？',
          target: PhotoTarget(face.padded(.012)),
          source: FindingSource.mlKit,
        ),
      );
    }
    for (final block in observations.blocks) {
      final candidates = <Finding>[];
      for (final text in block.texts.toSet()) {
        final hasContact = _email.hasMatch(text) || _phone.hasMatch(text);
        final registered = _matchedWord(text);
        candidates.add(
          Finding(
            id: 'block-${block.id}',
            kind: hasContact
                ? FindingKind.contact
                : registered != null
                ? FindingKind.privateWord
                : FindingKind.imageText,
            question: hasContact
                ? '連絡先のような文字が読めます。公開して大丈夫ですか？'
                : registered != null
                ? '登録ワード「$registered」が写っています。公開して大丈夫ですか？'
                : '写真の中の文字が読めます。公開してよい内容ですか？',
            target: PhotoTarget(block.region.padded(.006)),
            source: FindingSource.mlKit,
            excerpt: text,
            ruleEvidence: evidenceFor(text),
            targetKey: 'ocr:${block.id}',
          ),
        );
        // A contact and a registered word can coexist in one reading.
        if (hasContact && registered != null) {
          candidates.add(
            Finding(
              id: 'word-${block.id}',
              kind: FindingKind.privateWord,
              question: '登録ワード「$registered」が写っています。公開して大丈夫ですか？',
              target: PhotoTarget(block.region.padded(.006)),
              source: FindingSource.rule,
              excerpt: text,
              ruleEvidence: evidenceFor(text),
              targetKey: 'ocr:${block.id}',
            ),
          );
        }
      }
      int rank(Finding f) => switch (f.kind) {
        FindingKind.contact => 0,
        FindingKind.privateWord => 1,
        _ => 2,
      };
      candidates.sort((a, b) => rank(a).compareTo(rank(b)));
      found.addAll(mergeReviewFindings(candidates));
    }
    final caption = draft.caption;
    for (final pattern in [_email, _phone]) {
      for (final match in pattern.allMatches(caption)) {
        found.add(
          Finding(
            id: 'contact-${match.start}-${match.end}',
            kind: FindingKind.contact,
            question: '文章に連絡先のような記載があります。公開して大丈夫ですか？',
            target: CaptionTarget(TextSpanRange(match.start, match.end)),
            source: FindingSource.rule,
            excerpt: match.group(0)!,
          ),
        );
      }
    }
    for (final match in _future.allMatches(caption)) {
      found.add(
        Finding(
          id: 'future-${match.start}',
          kind: FindingKind.announcement,
          question: '今後の企画への言及があります。告知して大丈夫ですか？',
          target: CaptionTarget(TextSpanRange(match.start, match.end)),
          source: FindingSource.rule,
          excerpt: match.group(0)!,
        ),
      );
    }
    for (final word in [
      ...privateWords,
      ...activeVenueWords,
    ].map((e) => e.trim()).where((e) => e.isNotEmpty).toSet()) {
      for (final match in RegExp(
        RegExp.escape(word),
        caseSensitive: false,
      ).allMatches(caption)) {
        found.add(
          Finding(
            id: 'private-$word-${match.start}',
            kind: FindingKind.privateWord,
            question: '登録ワードへの言及があります。公開して大丈夫ですか？',
            target: CaptionTarget(TextSpanRange(match.start, match.end)),
            source: FindingSource.rule,
            excerpt: match.group(0)!,
            ruleEvidence: evidenceFor(word),
          ),
        );
      }
    }
    return found;
  }

  String? _matchedWord(String text) {
    for (final word in [...privateWords, ...activeVenueWords]) {
      if (word.trim().isNotEmpty &&
          text.toLowerCase().contains(word.trim().toLowerCase())) {
        return word.trim();
      }
    }
    return null;
  }
}
