import 'package:postcheck_rules/contracts.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:postcheck/adapters/image_processing.dart';
import 'package:postcheck/application/check_draft.dart';
import 'package:postcheck/domain/models.dart';
import 'package:postcheck/domain/ports.dart';
import 'package:postcheck/presentation/postcheck_controller.dart';

import 'controller_test.dart' show TestExport;

class _Pixels implements ImageProcessingPort {
  bool failNext = false;
  Completer<void>? nextRender;

  @override
  Future<PhotoInput> prepare(Uint8List bytes) async =>
      PhotoInput(bytes: bytes, width: 100, height: 100);

  @override
  Future<Uint8List> redact(
    PhotoInput photo,
    List<PhotoMask> regions, {
    RedactionStyle style = RedactionStyle.black,
  }) async {
    if (failNext) {
      failNext = false;
      throw StateError('synthetic rendering failure');
    }
    final gate = nextRender;
    nextRender = null;
    if (gate != null) await gate.future;
    return redactMaskRaster((photo, regions, style));
  }
}

class _Perception implements PerceptionPort {
  bool includeB = false;
  bool omitB = false;
  @override
  Future<Observations> inspect(PhotoInput photo) async {
    final source = img.decodeImage(photo.bytes)!;
    return Observations(
      blocks: [
        if (source.getPixel(20, 25).r != 0)
          const TextBlock(
            id: 'a',
            text: 'Sakura',
            region: ImageRegion(.1, .2, .3, .2),
          ),
        if (includeB && !omitB && source.getPixel(60, 25).r != 0)
          const TextBlock(
            id: 'b',
            text: 'Maple',
            region: ImageRegion(.5, .2, .2, .2),
          ),
      ],
    );
  }
}

class _Context implements ContextAnalysisPort {
  List<Finding> findings = const [];
  @override
  Future<ContextResult> analyze(
    DraftInput draft,
    Observations observations, {
    PublishedVenue? venue,
  }) async => ContextResult(status: '架空の検証結果', findings: findings);
}

Uint8List _white() {
  final raster = img.Image(width: 100, height: 100);
  img.fill(raster, color: img.ColorRgb8(255, 255, 255));
  return Uint8List.fromList(img.encodePng(raster));
}

int _red(Uint8List bytes, int x, int y) =>
    img.decodeImage(bytes)!.getPixel(x, y).r.toInt();

Finding _photo(PostCheckController c, String text) =>
    c.findings.firstWhere((f) => f.target is PhotoTarget && f.excerpt == text);
Finding _hidden(PostCheckController c, String text) =>
    c.hiddenFindings.firstWhere((f) => f.excerpt == text);

class _Fixture {
  _Fixture() {
    c = PostCheckController(
      check: CheckDraft(perception: perception, context: context),
      images: images,
      exporter: output,
      languageCode: () => 'ja',
    );
    addTearDown(c.dispose);
  }
  final perception = _Perception();
  final context = _Context();
  final images = _Pixels();
  final output = TestExport();
  late final PostCheckController c;

  Future<void> hideA() async {
    await c.loadPhoto(_white());
    await c.setRedactionStyle(RedactionStyle.black);
    await c.runCheck(const []);
    await c.decide(_photo(c, 'Sakura'), ReviewDecision.hide);
  }

  Future<Uint8List> shareWhenReviewed() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      for (final finding in c.findings.toList()) {
        if ((c.decisions[finding.id] ?? ReviewDecision.pending) ==
            ReviewDecision.pending) {
          await c.decide(finding, ReviewDecision.keep);
        }
      }
      if (!c.hasChanges) break;
      await c.applyAndRecheck(const []);
    }
    expect(c.canExport, isTrue);
    await c.share();
    expect(output.artifact, isNotNull);
    return output.artifact!.imageBytes!;
  }
}

Finding _reason({
  String question = '写真の背景を公開しますか？',
  String? ruleEvidence,
  List<Finding> related = const [],
  FindingTarget target = const WholePhotoTarget(),
}) => Finding(
  id: 'ai-0',
  kind: FindingKind.context,
  question: question,
  target: target,
  source: FindingSource.gemma,
  ruleEvidence: ruleEvidence,
  related: related,
);

void main() {
  test(
    'bulk hide and keep allow individual exceptions in both directions',
    () async {
      final f = _Fixture();
      f.perception.includeB = true;
      await f.c.loadPhoto(_white());
      await f.c.setRedactionStyle(RedactionStyle.black);
      f.c.setCaption('caption@example.com');
      await f.c.runCheck(const []);
      final caption = f.c.findings.singleWhere(
        (f) => f.target is CaptionTarget,
      );
      await f.c.decide(caption, ReviewDecision.hide);

      await f.c.decideAllPhotos(ReviewDecision.hide);
      expect(_red(f.c.previewBytes!, 20, 25), 0);
      expect(_red(f.c.previewBytes!, 60, 25), 0);
      await f.c.decide(_photo(f.c, 'Sakura'), ReviewDecision.keep);
      expect(_red(f.c.previewBytes!, 20, 25), 255);
      expect(_red(f.c.previewBytes!, 60, 25), 0);

      await f.c.decideAllPhotos(ReviewDecision.keep);
      expect(f.c.previewBytes, isNull);
      await f.c.decide(_photo(f.c, 'Sakura'), ReviewDecision.hide);
      expect(_red(f.c.previewBytes!, 20, 25), 0);
      expect(_red(f.c.previewBytes!, 60, 25), 255);
      expect(f.c.decisionFor(caption), ReviewDecision.hide);
      expect(f.c.outputCaption, isNot(contains('caption@example.com')));
    },
  );

  test(
    'bulk keep replays committed and pending photo masks together',
    () async {
      final f = _Fixture();
      f.perception.includeB = true;
      f.c.setCaption('caption@example.com');
      await f.hideA();
      await f.c.decide(
        f.c.findings.singleWhere((f) => f.target is CaptionTarget),
        ReviewDecision.hide,
      );
      await f.c.addManualRegion(const ImageRegion(.7, .7, .2, .2));
      await f.c.applyAndRecheck(const []);
      // A is already burned into the photo; B is a later pending selection.
      await f.c.decide(_photo(f.c, 'Maple'), ReviewDecision.hide);
      await f.c.decideAllPhotos(ReviewDecision.keep);
      expect(_red(f.c.photo!.bytes, 20, 25), 255);
      expect(_red(f.c.photo!.bytes, 60, 25), 255);
      expect(_red(f.c.photo!.bytes, 80, 80), 0);
      expect(f.c.hiddenFindings.where((f) => f.target is PhotoTarget), isEmpty);
      expect(f.c.hiddenFindings.single.target, isA<CaptionTarget>());
      expect(f.c.caption, isNot(contains('caption@example.com')));
      expect(f.c.findings.every((f) => f.target is PhotoTarget), isTrue);
      expect(
        f.c.findings.every(
          (item) => f.c.decisionFor(item) == ReviewDecision.keep,
        ),
        isTrue,
      );
      await f.c.decide(_photo(f.c, 'Maple'), ReviewDecision.hide);
      expect(_red(f.c.previewBytes!, 20, 25), 255);
      expect(_red(f.c.previewBytes!, 60, 25), 0);
      expect(_red(f.c.previewBytes!, 80, 80), 0);
    },
  );

  test(
    'all committed photo candidates can be restored then hidden individually',
    () async {
      final f = _Fixture();
      f.perception.includeB = true;
      await f.hideA();
      await f.c.decideAllPhotos(ReviewDecision.hide);
      await f.c.applyAndRecheck(const []);
      expect(f.c.hiddenFindings, hasLength(2));
      await f.c.decide(_hidden(f.c, 'Sakura'), ReviewDecision.keep);
      expect(_red(f.c.photo!.bytes, 20, 25), 255);
      expect(_red(f.c.photo!.bytes, 60, 25), 0);
      await f.c.decideAllPhotos(ReviewDecision.keep);
      expect(f.c.hiddenFindings, isEmpty);
      expect(_red(f.c.photo!.bytes, 20, 25), 255);
      expect(_red(f.c.photo!.bytes, 60, 25), 255);
      await f.c.decide(_photo(f.c, 'Sakura'), ReviewDecision.hide);
      expect(_red(f.c.previewBytes!, 60, 25), 255);
    },
  );

  test(
    'failed bulk restore keeps the protected photo and blocks export',
    () async {
      final f = _Fixture();
      f.perception.includeB = true;
      await f.hideA();
      await f.c.decideAllPhotos(ReviewDecision.hide);
      await f.c.addManualRegion(const ImageRegion(.7, .7, .2, .2));
      await f.c.applyAndRecheck(const []);
      final protected = Uint8List.fromList(f.c.photo!.bytes);
      f.images.failNext = true;
      await f.c.decideAllPhotos(ReviewDecision.keep);
      expect(f.c.photo!.bytes, orderedEquals(protected));
      expect(f.c.error, isNotEmpty);
      expect(f.c.canExport, isFalse);
      await f.c.runCheck(const []);
      expect(f.c.hiddenFindings, hasLength(2));
    },
  );

  test('cancelled bulk restore keeps every protected area', () async {
    final f = _Fixture();
    f.perception.includeB = true;
    await f.hideA();
    await f.c.decideAllPhotos(ReviewDecision.hide);
    await f.c.addManualRegion(const ImageRegion(.7, .7, .2, .2));
    await f.c.applyAndRecheck(const []);
    final protected = Uint8List.fromList(f.c.photo!.bytes);
    final gate = Completer<void>();
    f.images.nextRender = gate;
    final restore = f.c.decideAllPhotos(ReviewDecision.keep);
    await Future<void>.delayed(Duration.zero);
    f.c.cancelCheck();
    gate.complete();
    await restore;
    expect(f.c.photo!.bytes, orderedEquals(protected));
    expect(f.c.canExport, isFalse);
    await f.c.runCheck(const []);
    expect(f.c.hiddenFindings, hasLength(2));
  });

  test(
    'undo A preserves committed independent manual mask B in shared pixels',
    () async {
      final f = _Fixture();
      await f.hideA();
      await f.c.addManualRegion(const ImageRegion(.7, .7, .2, .2));
      await f.c.applyAndRecheck(const []);
      expect(_red(f.c.photo!.bytes, 80, 80), 0);
      // A later preference change must not weaken a previously black mask.
      await f.c.setRedactionStyle(RedactionStyle.blur);
      await f.c.decide(_hidden(f.c, 'Sakura'), ReviewDecision.keep);
      final shared = await f.shareWhenReviewed();
      expect(_red(shared, 20, 25), 255, reason: 'A was explicitly restored');
      expect(
        _red(shared, 80, 80),
        0,
        reason: 'B was never selected for removal',
      );
    },
  );

  test(
    'undo preserves mask batches when a later eraser crosses an earlier mask',
    () async {
      final f = _Fixture();
      await f.hideA();
      await f.c.addManualRegion(const ImageRegion(.7, .7, .2, .2));
      await f.c.applyAndRecheck(const []);
      await f.c.addManualMask(
        PhotoMask([
          MaskOperation(MaskOperationKind.erase, [
            const MaskPoint(.8, .8),
          ], diameter: .15),
        ]),
      );
      await f.c.applyAndRecheck(const []);
      expect(_red(f.c.photo!.bytes, 80, 80), 0);
      await f.c.decide(_hidden(f.c, 'Sakura'), ReviewDecision.keep);
      final shared = await f.shareWhenReviewed();
      expect(_red(shared, 20, 25), 255);
      expect(
        _red(shared, 80, 80),
        0,
        reason: 'An eraser in a later batch must not erase a previous batch',
      );
    },
  );

  for (final missing in [false, true]) {
    test(
      'undo A preserves adjusted automatic B even if not redetected ($missing)',
      () async {
        final f = _Fixture();
        f.perception.includeB = true;
        await f.hideA();
        await f.c.adjustRegion(
          _photo(f.c, 'Maple'),
          const ImageRegion(.45, .15, .35, .3),
        );
        await f.c.applyAndRecheck(const []);
        f.perception.omitB = missing;
        await f.c.decide(_hidden(f.c, 'Sakura'), ReviewDecision.keep);
        final shared = await f.shareWhenReviewed();
        expect(_red(shared, 20, 25), 255);
        expect(
          _red(shared, 76, 40),
          0,
          reason: 'B adjustment extends outside detected B',
        );
      },
    );
  }

  test(
    'undo A preserves pending manual masks on the current edited photo',
    () async {
      final f = _Fixture();
      await f.hideA();
      await f.c.applyAndRecheck(const []);
      await f.c.addManualRegion(const ImageRegion(.7, .7, .2, .2));
      expect(f.c.hasChanges, isTrue);
      await f.c.decide(_hidden(f.c, 'Sakura'), ReviewDecision.keep);
      final shared = await f.shareWhenReviewed();
      expect(_red(shared, 80, 80), 0);
    },
  );

  test(
    'undo a photo candidate preserves the latest unrelated caption edit',
    () async {
      final f = _Fixture();
      f.c.setCaption('最初の説明');
      await f.hideA();
      await f.c.applyAndRecheck(const []);
      await f.c.reviseCaption('後から修正した説明');
      await f.c.runCheck(const []);
      await f.c.decide(_hidden(f.c, 'Sakura'), ReviewDecision.keep);
      expect(f.c.caption, '後から修正した説明');
      await f.shareWhenReviewed();
      expect(f.output.artifact!.caption, '後から修正した説明');
    },
  );

  test('undo caption A preserves hidden caption B in shared text', () async {
    final f = _Fixture();
    f.c.setCaption('連絡先 a@example.com と b@example.com');
    await f.c.runCheck(const []);
    for (final finding in f.c.findings.toList()) {
      await f.c.decide(finding, ReviewDecision.hide);
    }
    await f.c.applyAndRecheck(const []);
    await f.c.decide(_hidden(f.c, 'a@example.com'), ReviewDecision.keep);
    expect(f.c.outputCaption, contains('a@example.com'));
    expect(f.c.outputCaption, isNot(contains('b@example.com')));
    for (final finding in f.c.findings.toList()) {
      if ((f.c.decisions[finding.id] ?? ReviewDecision.pending) ==
          ReviewDecision.pending) {
        await f.c.decide(finding, ReviewDecision.keep);
      }
    }
    if (f.c.hasChanges) await f.c.applyAndRecheck(const []);
    for (final finding in f.c.findings.toList()) {
      if ((f.c.decisions[finding.id] ?? ReviewDecision.pending) ==
          ReviewDecision.pending) {
        await f.c.decide(finding, ReviewDecision.keep);
      }
    }
    expect(f.c.canExport, isTrue);
    await f.c.share();
    expect(f.output.artifact!.caption, contains('a@example.com'));
    expect(f.output.artifact!.caption, isNot(contains('b@example.com')));
  });

  final evidenceChanges = <String, Finding>{
    'question': _reason(question: '未発表の製品を今公開して大丈夫ですか？'),
    'rule evidence': _reason(ruleEvidence: '施設の別の原文'),
    'related evidence': _reason(
      related: [
        const Finding(
          id: 'related',
          kind: FindingKind.privateWord,
          question: '登録ワードを公開しますか？',
          target: WholePhotoTarget(),
          source: FindingSource.rule,
          excerpt: '架空の企画名',
        ),
      ],
    ),
  };
  for (final entry in evidenceChanges.entries) {
    test('changed ${entry.key} requires a new decision after undo', () async {
      final f = _Fixture();
      await f.c.loadPhoto(_white());
      f.c.setCaption('連絡先 a@example.com');
      f.context.findings = [_reason()];
      await f.c.runCheck(const []);
      for (final finding in f.c.findings.toList()) {
        await f.c.decide(
          finding,
          finding.target is CaptionTarget
              ? ReviewDecision.hide
              : ReviewDecision.keep,
        );
      }
      await f.c.applyAndRecheck(const []);
      f.context.findings = [entry.value];
      await f.c.decide(_hidden(f.c, 'a@example.com'), ReviewDecision.keep);
      final changed = f.c.findings.firstWhere(
        (finding) => finding.source == FindingSource.gemma,
      );
      expect(
        f.c.decisions[changed.id] ?? ReviewDecision.pending,
        ReviewDecision.pending,
      );
      expect(f.c.canExport, isFalse);
    });
  }

  test('changed photo pixels do not inherit a whole-photo keep', () async {
    final f = _Fixture();
    await f.c.loadPhoto(_white());
    await f.c.setRedactionStyle(RedactionStyle.black);
    f.c.setCaption('連絡先 a@example.com');
    f.context.findings = [_reason()];
    await f.c.runCheck(const []);
    for (final finding in f.c.findings.toList()) {
      await f.c.decide(
        finding,
        finding.target is CaptionTarget
            ? ReviewDecision.hide
            : ReviewDecision.keep,
      );
    }
    await f.c.addManualRegion(const ImageRegion(.7, .7, .2, .2));
    await f.c.applyAndRecheck(const []);
    await f.c.decide(_hidden(f.c, 'a@example.com'), ReviewDecision.keep);
    final changed = f.c.findings.firstWhere(
      (finding) => finding.source == FindingSource.gemma,
    );
    expect(_red(f.c.photo!.bytes, 80, 80), 0);
    expect(
      f.c.decisions[changed.id] ?? ReviewDecision.pending,
      ReviewDecision.pending,
    );
    expect(f.c.canExport, isFalse);
  });

  test(
    'photo evidence precise coordinates are not rounded into an earlier keep',
    () async {
      final f = _Fixture();
      await f.c.loadPhoto(_white());
      f.c.setCaption('連絡先 a@example.com');
      f.context.findings = [
        _reason(target: const PhotoTarget(ImageRegion(.6, .6, .1, .1))),
      ];
      await f.c.runCheck(const []);
      for (final finding in f.c.findings.toList()) {
        await f.c.decide(
          finding,
          finding.target is CaptionTarget
              ? ReviewDecision.hide
              : ReviewDecision.keep,
        );
      }
      await f.c.applyAndRecheck(const []);
      f.context.findings = [
        _reason(target: const PhotoTarget(ImageRegion(.600001, .6, .1, .1))),
      ];
      await f.c.decide(_hidden(f.c, 'a@example.com'), ReviewDecision.keep);
      final changed = f.c.findings.firstWhere(
        (finding) => finding.source == FindingSource.gemma,
      );
      expect(
        f.c.decisions[changed.id] ?? ReviewDecision.pending,
        ReviewDecision.pending,
      );
      expect(f.c.canExport, isFalse);
    },
  );

  test('failed replay retains protected photo and blocks export', () async {
    final f = _Fixture();
    await f.hideA();
    await f.c.addManualRegion(const ImageRegion(.7, .7, .2, .2));
    await f.c.applyAndRecheck(const []);
    final protected = Uint8List.fromList(f.c.photo!.bytes);
    final hidden = _hidden(f.c, 'Sakura');
    f.images.failNext = true;
    await f.c.decide(hidden, ReviewDecision.keep);
    expect(f.c.photo!.bytes, orderedEquals(protected));
    expect(_red(f.c.photo!.bytes, 80, 80), 0);
    expect(f.c.canExport, isFalse);
    expect(f.c.error, isNotEmpty);
    await f.c.runCheck(const []);
    expect(
      f.c.hiddenFindings.map((finding) => finding.excerpt),
      contains('Sakura'),
    );
    await f.c.decide(_hidden(f.c, 'Sakura'), ReviewDecision.keep);
    final shared = await f.shareWhenReviewed();
    expect(_red(shared, 80, 80), 0);
  });

  test('cancelled replay retains protected photo and blocks export', () async {
    final f = _Fixture();
    await f.hideA();
    await f.c.addManualRegion(const ImageRegion(.7, .7, .2, .2));
    await f.c.applyAndRecheck(const []);
    final protected = Uint8List.fromList(f.c.photo!.bytes);
    final gate = Completer<void>();
    f.images.nextRender = gate;
    final replay = f.c.decide(_hidden(f.c, 'Sakura'), ReviewDecision.keep);
    await Future<void>.delayed(Duration.zero);
    f.c.cancelCheck();
    gate.complete();
    await replay;
    expect(f.c.photo!.bytes, orderedEquals(protected));
    expect(_red(f.c.photo!.bytes, 80, 80), 0);
    expect(f.c.canExport, isFalse);
  });

  for (final reset in [true, false]) {
    test(
      '${reset ? 'reset' : 'removePhoto'} clears stale hidden photo decisions',
      () async {
        final f = _Fixture();
        await f.hideA();
        await f.c.applyAndRecheck(const []);
        if (reset) {
          f.c.reset();
        } else {
          f.c.removePhoto();
        }
        expect(f.c.hiddenFindings, isEmpty);
        f.c.setCaption('新しい投稿');
        await f.c.runCheck(const []);
        expect(f.c.hiddenFindings, isEmpty);
        expect(
          f.c.reviewFindings.where((finding) => finding.excerpt == 'Sakura'),
          isEmpty,
        );
        await f.c.loadPhoto(_white());
        await f.c.runCheck(const []);
        expect(
          f.c.decisions[_photo(f.c, 'Sakura').id] ?? ReviewDecision.pending,
          ReviewDecision.pending,
        );
      },
    );
  }
}
