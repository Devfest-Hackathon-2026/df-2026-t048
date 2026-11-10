import 'dart:async';
import 'dart:convert';
import 'package:postcheck_rules/contracts.dart';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import '../application/check_draft.dart';
import '../application/review.dart';
import '../application/retained_caption.dart';
import '../domain/models.dart';
import '../domain/ports.dart';
import '../domain/social_share.dart';
import '../domain/preferences.dart';

final class PostCheckController extends ChangeNotifier {
  PostCheckController({
    required this.check,
    required this.images,
    required this.exporter,
    this.settings,
    this.saver,
    this.fileSaver,
    this.socialExporter,
    this.languageCode,
  });
  final CheckDraft check;
  final ImageProcessingPort images;
  final ExportPort exporter;
  final SettingsPort? settings;
  final PhotoSavePort? saver;
  final FileSavePort? fileSaver;
  final SocialExportPort? socialExporter;
  final String Function()? languageCode;
  bool photoPermissionDenied = false;
  String caption = '';
  PhotoInput? photo;
  PublishedVenue? venue;
  PublishedVenue? _pendingVenue;
  bool _hasPendingVenue = false;
  String _checkedRule = '';
  String get _ruleKey => venue == null
      ? ''
      : '${venue!.id}/${venue!.version}/${venue!.policy.rulesDigest}/${venue!.policy.validAt(DateTime.now())}/${venue!.policy.releaseAt?.isAfter(DateTime.now())}/${venue!.policy.activeWords(DateTime.now()).join('|')}';
  void reconcileVenue(List<PublishedVenue> catalog) {
    final old = venue;
    if (old == null) return;
    final current = catalog.where((v) => v.id == old.id).firstOrNull;
    if (current == null ||
        current.version != old.version ||
        current.policy.rulesDigest != old.policy.rulesDigest) {
      _queueVenue(current);
    }
  }

  void expireVenue() {
    if (venue == null) return;
    if (!venue!.policy.validAt(DateTime.now())) {
      _queueVenue(null);
    } else if (report != null && _checkedRule != _ruleKey) {
      _queueVenue(venue);
    }
  }

  void _queueVenue(PublishedVenue? next) {
    _pendingVenue = next;
    _hasPendingVenue = true;
    _emit();
  }

  void selectVenue(PublishedVenue? value) {
    if (busy || preparingPreview || !commitEditsForDraft()) return;
    venue = value;
    _invalidate();
    _emit();
  }

  CheckReport? report;
  final decisions = <String, ReviewDecision>{};
  final manualRegions = <PhotoMask>[];
  final _overrides = <String, PhotoMask>{};
  final _learned = <String>{};
  bool busy = false, preparingPreview = false, drawing = false;
  String progress = '', error = '';
  bool _canFinishCheck = false, _finishRequested = false;
  bool get canFinishCheck => busy && _canFinishCheck && !_finishRequested;
  void finishWithCurrentResults() {
    if (!canFinishCheck) return;
    _finishRequested = true;
    _emit();
  }

  String? selectedId;
  Uint8List? previewBytes;
  RedactionStyle redactionStyle = RedactionStyle.blur;
  RedactionStyle get effectiveRedactionStyle => redactionStyle;
  int _revision = 0, _job = 0;
  bool _disposed = false;
  DraftInput? _original;

  // Only exact evidence matches may reuse an earlier decision.
  final Map<String, ReviewDecision> _priorDecisions = {};
  final Set<String> _priorKeeps = {};
  String _checkedInputKey = "";
  // Rows for candidates hidden by an earlier recheck. They are shown next to
  // the current findings with 「隠す」 selected, so kept and hidden items read
  // the same way; choosing 「残す」 removes only that candidate's edit.
  final Map<String, Finding> _hiddenRows = {};
  // Position of each candidate in the first check that showed it, so rows
  // keep their original order instead of moving hidden ones to the end.
  final Map<String, int> _order = {};
  List<String> _lastWords = const [];
  PhotoInput? _redactionSource;
  final List<_AppliedPhotoEdit> _photoEdits = [];
  RetainedCaption? _retainedCaption;
  int appliedEdits = 0;
  bool rechecked = false;
  ReviewPreferences get policy =>
      settings?.reviewPreferences ?? const ReviewPreferences();
  /// Candidates of the last check, without the items the user switched off
  /// on the review settings page (venue-rule candidates are always kept).
  List<Finding> get findings {
    final checks = venue?.policy.validAt(DateTime.now()) == true
        ? venue!.policy.checkTargets
        : const <String>[];
    return report?.findings
            .where((f) => policy.shows(f, venueTargets: checks))
            .toList() ??
        [];
  }
  Finding? get selected {
    for (final f in findings) {
      if (f.id == selectedId) return f;
    }
    return findings.isEmpty ? null : findings.first;
  }

  int get pendingCount => findings
      .where(
        (f) =>
            (decisions[f.id] ?? ReviewDecision.pending) ==
            ReviewDecision.pending,
      )
      .length;
  bool get canCheck =>
      !busy &&
      !preparingPreview &&
      (photo != null || caption.trim().isNotEmpty);
  bool get hasChanges => masks.isNotEmpty || outputCaption != caption;
  bool get canExport =>
      report != null &&
      !_hasPendingVenue &&
      _checkedRule == _ruleKey &&
      pendingCount == 0 &&
      !busy &&
      !preparingPreview &&
      !hasChanges &&
      error.isEmpty;
  String get outputCaption => selectedCaption(
    caption,
    findings,
    decisions,
    marker: redactionMarkerFor(languageCode?.call() ?? 'ja'),
  );
  PhotoMask maskFor(Finding f) =>
      _overrides[f.id] ?? PhotoMask.region((f.target as PhotoTarget).region);
  List<PhotoMask> get masks => [
    for (final f in findings)
      if (decisions[f.id] == ReviewDecision.hide && f.target is PhotoTarget)
        maskFor(f),
    ...manualRegions,
  ];
  void _emit() {
    if (_disposed) return;
    if (_hasPendingVenue && !busy && !preparingPreview && error.isEmpty) {
      final next = _pendingVenue;
      _hasPendingVenue = false;
      if (commitEditsForDraft()) {
        venue = next;
        _invalidate();
      } else {
        _hasPendingVenue = true;
      }
    }
    notifyListeners();
  }

  bool _current(int job) => !_disposed && job == _job;
  void _invalidate() {
    _revision++;
    _job++;
    report = null;
    _checkedInputKey = "";
    _canFinishCheck = false;
    _finishRequested = false;
    decisions.clear();
    manualRegions.clear();
    _overrides.clear();
    _learned.clear();
    previewBytes = null;
    selectedId = null;
    preparingPreview = false;
    drawing = false;
    error = '';
    rechecked = false;
  }

  void setCaption(String value) {
    if (value == caption || busy) return;
    _retainedCaption?.revise(value);
    caption = value;
    _invalidate();
    _emit();
  }

  /// Caption editor commits existing masks first, so changing text never discards them.
  Future<void> reviseCaption(String value) async {
    if (busy || preparingPreview || error.isNotEmpty) return;
    _rememberOriginal();
    _rememberDecisions();
    _commitCaption();
    _commitImage();
    _retainedCaption?.revise(value);
    caption = value;
    appliedEdits++;
    _invalidate();
    _emit();
  }

  void _rememberOriginal() =>
      _original ??= DraftInput(caption: caption, photo: photo);
  bool commitEditsForDraft() {
    if (busy || preparingPreview || error.isNotEmpty) return false;
    if (!hasChanges) return true;
    _rememberOriginal();
    _rememberDecisions();
    _commitCaption();
    _commitImage();
    appliedEdits++;
    _invalidate();
    _emit();
    return true;
  }

  void retryExport() {
    if (!busy && !hasChanges && report != null) {
      error = '';
      photoPermissionDenied = false;
      _emit();
    }
  }

  static String _signature(Finding f) {
    Object evidence(Finding item) => [
      item.kind.name,
      item.source.name,
      item.excerpt,
      item.question,
      item.ruleEvidence,
      switch (item.target) {
        PhotoTarget(:final region) => [
          'photo',
          region.x,
          region.y,
          region.width,
          region.height,
          if (region.outline != null)
            [
              for (final p in region.outline!) [p.x, p.y],
            ],
        ],
        CaptionTarget(:final range) => ['caption', range.start, range.end],
        WholePhotoTarget() => ['whole'],
      },
      [for (final related in item.related) evidence(related)],
    ];
    return jsonEncode(evidence(f));
  }

  String _decisionSignature(Finding f) =>
      jsonEncode([_checkedInputKey, _checkedRule, _signature(f)]);

  static String _inputKey(DraftInput draft) => jsonEncode([
    sha256.convert(utf8.encode(draft.caption)).toString(),
    if (draft.photo != null)
      [
        draft.photo!.width,
        draft.photo!.height,
        sha256.convert(draft.photo!.bytes).toString(),
      ],
  ]);

  void _rememberDecisions() {
    for (final f in findings) {
      final d = decisions[f.id] ?? ReviewDecision.pending;
      final decisionKey = _decisionSignature(f);
      if (d == ReviewDecision.keep) {
        _priorKeeps.add(decisionKey);
      } else {
        _priorKeeps.remove(decisionKey);
      }
      if (d == ReviewDecision.pending) continue;
      final key = _signature(f);
      _priorDecisions[key] = d;
      if (d == ReviewDecision.hide && f.target is! WholePhotoTarget) {
        _hiddenRows.putIfAbsent(
          key,
          () => Finding(
            id: 'hidden:$key',
            kind: f.kind,
            question: f.question,
            target: f.target,
            source: f.source,
            excerpt: f.excerpt,
            ruleEvidence: f.ruleEvidence,
            targetKey: f.targetKey,
            related: f.related,
          ),
        );
      } else {
        _hiddenRows.remove(key);
      }
    }
  }

  void _forgetDecisions() {
    _priorDecisions.clear();
    _priorKeeps.clear();
    _hiddenRows.clear();
    _order.clear();
    _photoEdits.clear();
    _redactionSource = null;
    _retainedCaption = null;
  }

  /// Earlier 「隠す」 candidates that the edited copy no longer contains.
  List<Finding> get hiddenFindings {
    if (_original == null || report == null) return const [];
    final current = findings.map(_signature).toSet();
    return [
      for (final entry in _hiddenRows.entries)
        if (!current.contains(entry.key) &&
            _priorDecisions[entry.key] == ReviewDecision.hide)
          entry.value,
    ];
  }

  /// What the review list and photo numbers show: current findings and
  /// earlier hidden ones, in the order they first appeared.
  List<Finding> get reviewFindings {
    final rows = [...findings, ...hiddenFindings];
    final keyed =
        [
          for (var i = 0; i < rows.length; i++)
            (order: _order[_signature(rows[i])] ?? _order.length + i, index: i),
        ]..sort(
          (a, b) => a.order != b.order
              ? a.order.compareTo(b.order)
              : a.index.compareTo(b.index),
        );
    return [for (final k in keyed) rows[k.index]];
  }

  /// Decisions for [reviewFindings], with earlier hidden rows as 「隠す」.
  Map<String, ReviewDecision> get reviewDecisions => {
    ...decisions,
    for (final f in hiddenFindings) f.id: ReviewDecision.hide,
  };

  bool isHiddenEarlier(Finding f) => _hiddenRows.values.contains(f);

  ReviewDecision decisionFor(Finding f) => isHiddenEarlier(f)
      ? ReviewDecision.hide
      : decisions[f.id] ?? ReviewDecision.pending;

  bool canReselect(Finding finding) {
    if (!isHiddenEarlier(finding) &&
        !_hiddenRows.containsKey(_signature(finding))) {
      return true;
    }
    if (finding.target is! CaptionTarget) return true;
    return _retainedCaption?.canRestore(_signature(finding)) ?? false;
  }

  void _commitCaption() {
    final history = _retainedCaption ??= RetainedCaption(caption);
    history.revise(caption);
    history.hide({
      for (final f in findings)
        if (decisions[f.id] == ReviewDecision.hide && f.target is CaptionTarget)
          _signature(f): (f.target as CaptionTarget).range,
    }, marker: redactionMarkerFor(languageCode?.call() ?? 'ja'));
    caption = history.text;
  }

  void _commitImage() {
    if (photo != null && previewBytes != null && masks.isNotEmpty) {
      _redactionSource ??= photo;
      _photoEdits.add(
        _AppliedPhotoEdit(
          style: effectiveRedactionStyle,
          masks: [
            for (final f in findings)
              if (decisions[f.id] == ReviewDecision.hide &&
                  f.target is PhotoTarget)
                (key: _signature(f), mask: maskFor(f)),
            for (final mask in manualRegions) (key: null, mask: mask),
          ],
        ),
      );
      photo = PhotoInput(
        bytes: previewBytes!,
        width: photo!.width,
        height: photo!.height,
      );
    }
  }

  Future<void> loadPhoto(Uint8List bytes) async {
    if (busy) return;
    final job = ++_job;
    busy = true;
    error = '';
    progress = '写真を端末内で準備しています';
    _emit();
    try {
      final prepared = await images.prepare(bytes);
      if (!_current(job)) return;
      photo = prepared;
      _original = null;
      _forgetDecisions();
      appliedEdits = 0;
      busy = false;
      _invalidate();
    } on FormatException catch (e) {
      if (_current(job)) {
        error = e.message;
        busy = false;
      }
    } catch (_) {
      if (_current(job)) {
        error = '写真を読み込めませんでした。別の写真を選んでください。';
        busy = false;
      }
    }
    _emit();
  }

  void removePhoto() {
    if (busy) return;
    photo = null;
    _original = null;
    _forgetDecisions();
    appliedEdits = 0;
    _invalidate();
    _emit();
  }

  void cancelCheck() {
    _job++;
    _revision++;
    busy = false;
    _canFinishCheck = false;
    preparingPreview = false;
    progress = '';
    report = null;
    error = '';
    _emit();
  }

  Future<void> runCheck(List<String> words) async {
    expireVenue();
    if (!canCheck) return;
    _lastWords = List.of(words);
    _invalidate();
    final job = _job;
    busy = true;
    progress = '写真と文章を確認しています';
    _emit();
    final draft = DraftInput(caption: caption, photo: photo);
    final ruleAtStart = _ruleKey;
    try {
      final result = await check(
        draft,
        privateWords: words,
        venue: venue,
        isCancelled: () => !_current(job),
        finishRequested: () => _finishRequested,
        onCanFinish: () {
          if (_current(job)) {
            _canFinishCheck = true;
            _emit();
          }
        },
        onProgress: (message) {
          if (_current(job)) {
            progress = message;
            _emit();
          }
        },
      );
      if (!_current(job)) return;
      if (ruleAtStart != _ruleKey || _hasPendingVenue) {
        progress = '施設ルールが更新されました。もう一度チェックしてください。';
        return;
      }
      _checkedRule = ruleAtStart;
      report = result;
      _checkedInputKey = _inputKey(draft);
      for (final f in result.findings) {
        _order.putIfAbsent(_signature(f), () => _order.length);
      }
      selectedId = findings.firstOrNull?.id;
    } catch (_) {
      if (_current(job)) error = 'チェックを完了できませんでした。もう一度お試しください。';
    } finally {
      if (_current(job)) {
        busy = false;
        _canFinishCheck = false;
        _emit();
      }
    }
  }

  void select(String id) {
    selectedId = id;
    _emit();
  }

  void toggleDrawing() {
    drawing = !drawing;
    _emit();
  }

  Future<void> decide(
    Finding finding,
    ReviewDecision decision, {
    bool remember = false,
  }) async {
    if (isHiddenEarlier(finding) ||
        (decision == ReviewDecision.keep &&
            _hiddenRows.containsKey(_signature(finding)))) {
      if (busy || decision == ReviewDecision.hide || !canReselect(finding)) {
        return;
      }
      final key = _signature(finding);
      await _reselectHidden(
        settings?.privateWords ?? _lastWords,
        keys: {key},
        decision: decision,
      );
      return;
    }
    if (busy ||
        !findings.contains(finding) ||
        (decision == ReviewDecision.hide &&
            finding.target is WholePhotoTarget)) {
      return;
    }
    decisions[finding.id] = decision;
    selectedId = finding.id;
    if (remember && settings != null && !_learned.contains(finding.id)) {
      _learned.add(finding.id);
      try {
        await settings!.recordChoice(finding, decision);
      } catch (_) {
        error = '学習した傾向を保存できませんでした。';
      }
    }
    await _updatePreview();
  }

  /// Apply one choice to the photo candidates shown now. Caption decisions,
  /// and manual masks stay independent.
  Future<void> decideAllPhotos(ReviewDecision decision) async {
    if (busy ||
        preparingPreview ||
        report == null ||
        photo == null ||
        decision == ReviewDecision.pending) {
      return;
    }
    final rows = reviewFindings
        .where((f) => f.target is! CaptionTarget)
        .toList();
    if (decision == ReviewDecision.keep) {
      final eligible = rows.where(canReselect);
      final keys = {
        for (final f in eligible)
          if (_hiddenRows.containsKey(_signature(f))) _signature(f),
      };
      if (keys.isNotEmpty) {
        // Pending photo masks will be committed before replay too; remove
        // those selected by this same bulk action in the same reconstruction.
        keys.addAll(
          eligible
              .where(
                (f) =>
                    f.target is PhotoTarget &&
                    decisionFor(f) == ReviewDecision.hide,
              )
              .map(_signature),
        );
        await _reselectHidden(
          settings?.privateWords ?? _lastWords,
          keys: keys,
          decision: decision,
          additionalKeeps: eligible.map(_signature).toSet(),
        );
        return;
      }
    }
    for (final f in rows) {
      if (!findings.contains(f) ||
          (decision == ReviewDecision.hide && f.target is WholePhotoTarget)) {
        continue;
      }
      decisions[f.id] = decision;
    }
    // One render for the whole batch; individual rows remain editable.
    await _updatePreview();
  }

  Future<void> applySuggestions() async {
    if (busy || preparingPreview) return;
    for (final f in findings) {
      final suggestion = policy.suggestionFor(f);
      if ((decisions[f.id] ?? ReviewDecision.pending) !=
              ReviewDecision.pending ||
          suggestion == null) {
        continue;
      }
      if (suggestion == ReviewDecision.hide && f.target is WholePhotoTarget) {
        continue;
      }
      decisions[f.id] = suggestion;
    }
    await _updatePreview();
  }

  Future<void> adjustRegion(Finding finding, ImageRegion region) =>
      adjustMask(finding, PhotoMask.region(region));

  Future<void> adjustMask(Finding finding, PhotoMask region) async {
    if (!region.isValid || busy || !findings.contains(finding)) return;
    if (finding.target is PhotoTarget) {
      _overrides[finding.id] = region;
      decisions[finding.id] = ReviewDecision.hide;
      await _updatePreview();
    } else {
      selectedId = finding.id;
      await addManualMask(region);
    }
  }

  Future<void> addManualRegion(ImageRegion region) =>
      addManualMask(PhotoMask.region(region));

  Future<void> addManualMask(PhotoMask region) async {
    if (!region.isValid || busy) return;
    manualRegions.add(region);
    for (final f in findings) {
      if (f.id == selectedId && f.target is WholePhotoTarget) {
        decisions[f.id] = ReviewDecision.hide;
      }
    }
    drawing = false;
    await _updatePreview();
  }

  Future<void> replaceManualMask(PhotoMask mask) async {
    if (!mask.isValid || busy || preparingPreview) return;
    manualRegions.clear();
    if (!mask.isEmpty) manualRegions.add(mask);
    await _updatePreview();
  }

  Future<void> undoManualRegion() async {
    if (manualRegions.isEmpty || busy) return;
    manualRegions.removeLast();
    for (final f in findings) {
      if (f.target is WholePhotoTarget &&
          decisions[f.id] == ReviewDecision.hide) {
        decisions[f.id] = ReviewDecision.pending;
      }
    }
    await _updatePreview();
  }

  Future<void> resetEdits() async {
    if (busy) return;
    _priorKeeps.clear();
    _priorDecisions.removeWhere(
      (_, decision) => decision == ReviewDecision.keep,
    );
    decisions.clear();
    manualRegions.clear();
    _overrides.clear();
    await _updatePreview();
  }

  Future<void> restoreOriginal() async {
    if (busy || _original == null) return;
    caption = _original!.caption;
    photo = _original!.photo;
    _original = null;
    _forgetDecisions();
    appliedEdits = 0;
    _invalidate();
    _emit();
  }

  bool get canRestoreOriginal => _original != null;
  bool get canReselectHidden => _original != null && !busy && !preparingPreview;

  /// Rebuild only the selected edits. Other committed and pending masks and
  /// the latest caption stay protected, even if detection no longer finds them.
  Future<void> _reselectHidden(
    List<String> words, {
    required Set<String> keys,
    required ReviewDecision decision,
    Set<String> additionalKeeps = const {},
  }) async {
    if (!canReselectHidden || error.isNotEmpty) return;
    _rememberDecisions();
    final hidden = {
      for (final key in keys)
        if (_hiddenRows[key] case final Finding finding)
          if (canReselect(finding)) key: finding,
    };
    if (hidden.isEmpty) return;
    final carriedKeeps = Set.of(_priorKeeps);
    _commitCaption();
    _commitImage();
    // The current report refers to the old pixels/ranges. Invalidate it before
    // doing asynchronous work so cancellation/failure can never enable export.
    _invalidate();
    if (hidden.entries.any(
      (entry) =>
          entry.value.target is CaptionTarget &&
          !(_retainedCaption?.canRestore(entry.key) ?? false),
    )) {
      await runCheck(words);
      return;
    }
    final restorationJob = _job;
    busy = true;
    progress = '選んだ候補だけを戻しています';
    _emit();
    try {
      if (hidden.values.any((f) => f.target is PhotoTarget)) {
        final source = _redactionSource;
        if (source == null) throw StateError('missing_redaction_source');
        var rebuilt = source;
        for (final edit in _photoEdits) {
          final masks = [
            for (final item in edit.masks)
              if (!hidden.containsKey(item.key)) item.mask,
          ];
          if (masks.isEmpty) continue;
          final bytes = await images.redact(rebuilt, masks, style: edit.style);
          if (!_current(restorationJob)) return;
          rebuilt = PhotoInput(
            bytes: bytes,
            width: rebuilt.width,
            height: rebuilt.height,
          );
        }
        if (!_current(restorationJob)) return;
        photo = rebuilt;
        for (final edit in _photoEdits) {
          edit.masks.removeWhere((item) => hidden.containsKey(item.key));
        }
      }
      for (final entry in hidden.entries) {
        if (entry.value.target is CaptionTarget) {
          if (!_retainedCaption!.restore(entry.key)) {
            throw StateError('caption_changed');
          }
          caption = _retainedCaption!.text;
        }
        _hiddenRows.remove(entry.key);
        _priorDecisions[entry.key] = decision;
      }
      appliedEdits++;
    } catch (_) {
      if (_current(restorationJob)) {
        error = '選択を戻せませんでした。現在の修正内容は保持しています。もう一度お試しください。';
      }
      return;
    } finally {
      if (_current(restorationJob)) {
        busy = false;
        _emit();
      }
    }
    if (!_current(restorationJob)) return;
    final operation = runCheck(words);
    final checkJob = _job;
    await operation;
    if (!_current(checkJob) || report == null) return;
    for (final f in findings) {
      // Hidden edits remaining in the ledger already exist in the checked
      // pixels/text. Explicit bulk choices apply only to the exact candidates
      // shown at the start; new or changed evidence still needs review.
      final selected =
          (hidden.containsKey(_signature(f)) ||
              additionalKeeps.contains(_signature(f))) &&
          decision == ReviewDecision.keep;
      if (!selected && !carriedKeeps.contains(_decisionSignature(f))) {
        continue;
      }
      decisions[f.id] = ReviewDecision.keep;
      if (hidden.containsKey(_signature(f))) selectedId = f.id;
    }
    await _updatePreview();
  }

  Future<void> setRedactionStyle(RedactionStyle style) async {
    if (busy || preparingPreview || redactionStyle == style) return;
    redactionStyle = style;
    await _updatePreview();
  }

  Future<void> _updatePreview() async {
    final version = ++_revision;
    final regions = masks;
    error = '';
    previewBytes = null;
    if (photo == null || regions.isEmpty) {
      preparingPreview = false;
      _emit();
      return;
    }
    preparingPreview = true;
    _emit();
    try {
      final bytes = await images.redact(
        photo!,
        regions,
        style: effectiveRedactionStyle,
      );
      if (!_disposed && version == _revision) {
        previewBytes = bytes;
        error = '';
      }
    } catch (_) {
      if (version == _revision) error = 'マスク画像を作成できませんでした。もう一度選択してください。';
    } finally {
      if (!_disposed && version == _revision) {
        preparingPreview = false;
        _emit();
      }
    }
  }

  Future<void> applyAndRecheck(List<String> words) async {
    if (busy || preparingPreview || report == null || error.isNotEmpty) return;
    _rememberOriginal();
    _rememberDecisions();
    final changed = hasChanges;
    _commitCaption();
    _commitImage();
    if (changed) appliedEdits++;
    final operation = runCheck(words);
    final job = _job;
    await operation;
    if (_current(job) && report != null) {
      rechecked = true;
      _emit();
    }
  }

  Future<ExportArtifact> _shareArtifact() async => ExportArtifact(
    caption: caption,
    imageBytes: photo == null ? null : await images.redact(photo!, const []),
  );

  Future<Uint8List> previewStory(StoryLayout layout) async {
    if (!canExport || socialExporter == null) {
      throw StateError('review_required');
    }
    final revision = _revision;
    final artifact = await _shareArtifact();
    final png = await socialExporter!.previewStory(artifact, layout);
    if (_disposed || revision != _revision || !canExport) {
      throw StateError('review_required');
    }
    return png;
  }

  Future<ShareHandoff?> shareTo(
    ShareDestination destination, {
    StoryLayout layout = StoryLayout.card,
    String? officialLineId,
    double? x,
    double? y,
  }) async {
    if (!canExport || socialExporter == null) return null;
    busy = true;
    progress = '共有する内容を準備しています';
    _emit();
    try {
      return await socialExporter!.shareTo(
        await _shareArtifact(),
        destination,
        storyLayout: layout,
        officialLineId: officialLineId,
        anchorX: x,
        anchorY: y,
      );
    } on StoryCaptionTooLong {
      error = '文章が長く、ストーリーズ画像に収まりません。写真のみを選ぶか、文章を短くして再確認してください。';
    } on InvalidLineAccount {
      error = '公式LINEを開けませんでした。アカウントIDとLINEのインストールを確認してください。';
    } catch (_) {
      error = '共有先を開けませんでした。もう一度お試しください。';
    } finally {
      busy = false;
      _emit();
    }
    return null;
  }

  Future<void> share({double? x, double? y}) async {
    if (!canExport) return;
    busy = true;
    progress = '書き出し画像を準備しています';
    _emit();
    try {
      final image = photo == null
          ? null
          : await images.redact(photo!, const []);
      await exporter.share(
        ExportArtifact(caption: caption, imageBytes: image),
        anchorX: x,
        anchorY: y,
      );
    } catch (_) {
      error = '書き出せませんでした。もう一度お試しください。';
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<bool> savePhoto() async {
    if (!canExport || photo == null || saver == null) return false;
    busy = true;
    photoPermissionDenied = false;
    progress = '写真ライブラリに保存しています';
    _emit();
    try {
      await saver!.savePhoto(await images.redact(photo!, const []));
      return true;
    } on PhotoPermissionDenied {
      photoPermissionDenied = true;
      error = '写真への追加が許可されていません。設定で許可してください。';
      return false;
    } catch (_) {
      error = '写真に保存できませんでした。空き容量を確認して、もう一度お試しください。';
      return false;
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<bool> saveFile() async {
    if (!canExport || photo == null || fileSaver == null) return false;
    busy = true;
    progress = '保存する写真を準備しています';
    _emit();
    try {
      return await fileSaver!.saveFile(await images.redact(photo!, const []));
    } catch (_) {
      error = 'ファイルに保存できませんでした。保存先や空き容量を確認してください。';
      return false;
    } finally {
      busy = false;
      _emit();
    }
  }

  void reset() {
    if (busy) return;
    caption = '';
    photo = null;
    venue = null;
    _hasPendingVenue = false;
    _original = null;
    _forgetDecisions();
    appliedEdits = 0;
    _invalidate();
    _emit();
  }

  void invalidateConfiguration() {
    if (!busy) {
      _invalidate();
      _emit();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _job++;
    _revision++;
    super.dispose();
  }
}

/// Each batch is applied to the output of the previous one. This preserves
/// redaction styles and brush/eraser ordering across multiple rechecks.
final class _AppliedPhotoEdit {
  _AppliedPhotoEdit({required this.style, required this.masks});
  final RedactionStyle style;
  final List<({String? key, PhotoMask mask})> masks;
}
