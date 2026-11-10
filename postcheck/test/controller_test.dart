import 'package:postcheck_rules/contracts.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:postcheck/application/check_draft.dart';
import 'package:postcheck/domain/models.dart';
import 'package:postcheck/domain/ports.dart';
import 'package:postcheck/presentation/postcheck_controller.dart';

class TestPerception implements PerceptionPort {
  @override
  Future<Observations> inspect(PhotoInput photo) async => const Observations(
    blocks: [
      TextBlock(
        id: 'b0',
        text: 'taro@example.com',
        region: ImageRegion(.1, .2, .3, .2),
      ),
    ],
  );
}

class _RedactionAwarePerception extends TestPerception {
  @override
  Future<Observations> inspect(PhotoInput photo) async =>
      photo.bytes.length == 1 && photo.bytes.single == 9
      ? const Observations()
      : super.inspect(photo);
}

class TestContext implements ContextAnalysisPort {
  TestContext({this.findings = const []});
  final List<Finding> findings;
  @override
  Future<ContextResult> analyze(
    DraftInput draft,
    Observations observations, {
    PublishedVenue? venue,
  }) async => ContextResult(status: 'テスト用・AIなし', findings: findings);
}

class TestImages implements ImageProcessingPort {
  Completer<Uint8List>? pending;
  final rendered = <List<PhotoMask>>[];
  final styles = <RedactionStyle>[];
  @override
  Future<PhotoInput> prepare(Uint8List bytes) async =>
      PhotoInput(bytes: bytes, width: 100, height: 100);
  @override
  Future<Uint8List> redact(
    PhotoInput photo,
    List<PhotoMask> regions, {
    RedactionStyle style = RedactionStyle.black,
  }) async {
    rendered.add(regions);
    styles.add(style);
    return pending == null ? Uint8List.fromList([9]) : pending!.future;
  }
}

class TestExport implements ExportPort {
  ExportArtifact? artifact;
  @override
  Future<void> share(
    ExportArtifact value, {
    double? anchorX,
    double? anchorY,
  }) async {
    artifact = value;
  }
}

void main() {
  late TestImages images;
  late TestExport output;
  late PostCheckController controller;
  setUp(() {
    images = TestImages();
    output = TestExport();
    controller = PostCheckController(
      check: CheckDraft(perception: TestPerception(), context: TestContext()),
      images: images,
      exporter: output,
    );
  });
  tearDown(() => controller.dispose());

  test('photo masking changes style and retains recheck gate', () async {
    await controller.loadPhoto(Uint8List.fromList([1]));
    await controller.runCheck([]);
    final finding = controller.findings.firstWhere(
      (f) => f.target is PhotoTarget,
    );
    await controller.decide(finding, ReviewDecision.hide);
    expect(images.styles.last, RedactionStyle.blur);
    expect(controller.canExport, isFalse);
    await controller.setRedactionStyle(RedactionStyle.black);
    expect(images.styles.last, RedactionStyle.black);
    expect(controller.canExport, isFalse);
  });

  test(
    'manual masking resolves whole-photo candidate and undo requires review again',
    () async {
      final context = TestContext(
        findings: const [
          Finding(
            id: 'whole',
            kind: FindingKind.context,
            question: '背景を公開して大丈夫ですか？',
            target: WholePhotoTarget(),
            source: FindingSource.gemma,
          ),
        ],
      );
      final subject = PostCheckController(
        check: CheckDraft(perception: TestPerception(), context: context),
        images: images,
        exporter: output,
      );
      addTearDown(subject.dispose);
      await subject.loadPhoto(Uint8List.fromList([1]));
      await subject.runCheck([]);
      subject.select('whole');
      await subject.addManualRegion(const ImageRegion(.1, .1, .3, .3));
      expect(subject.decisions['whole'], ReviewDecision.hide);
      await subject.undoManualRegion();
      expect(subject.decisions['whole'], ReviewDecision.pending);
      expect(subject.canExport, isFalse);
    },
  );

  test(
    'editing input invalidates reviewed results and blocks export',
    () async {
      controller.setCaption('メール taro@example.com');
      await controller.runCheck([]);
      expect(controller.canExport, isFalse);
      await controller.decide(controller.findings.single, ReviewDecision.keep);
      expect(controller.canExport, isTrue);
      controller.setCaption('別の下書き');
      expect(controller.report, isNull);
      expect(controller.canExport, isFalse);
      await controller.share();
      expect(output.artifact, isNull);
    },
  );

  test('export includes only edited caption and rasterized photo', () async {
    controller.dispose();
    controller = PostCheckController(
      check: CheckDraft(
        perception: _RedactionAwarePerception(),
        context: TestContext(),
      ),
      images: images,
      exporter: output,
    );
    controller.setCaption('連絡先 taro@example.com');
    await controller.loadPhoto(Uint8List.fromList([1, 2, 3]));
    await controller.runCheck([]);
    for (final finding in controller.findings) {
      await controller.decide(finding, ReviewDecision.hide);
    }
    expect(controller.canExport, isFalse);
    await controller.applyAndRecheck([]);
    for (final f in controller.findings) {
      await controller.decide(f, ReviewDecision.keep);
    }
    await controller.share();
    expect(output.artifact!.caption, '連絡先 ［非表示］');
    expect(output.artifact!.imageBytes, [9]);
    expect(images.rendered.last, isEmpty);
    expect(controller.photo!.bytes, [9]);
  });

  test('late mask rendering cannot restore a removed photo', () async {
    await controller.loadPhoto(Uint8List.fromList([1]));
    await controller.runCheck([]);
    images.pending = Completer<Uint8List>();
    final work = controller.decide(
      controller.findings.single,
      ReviewDecision.hide,
    );
    expect(controller.preparingPreview, isTrue);
    controller.removePhoto();
    images.pending!.complete(Uint8List.fromList([8]));
    await work;
    expect(controller.photo, isNull);
    expect(controller.previewBytes, isNull);
    expect(controller.preparingPreview, isFalse);
  });

  test(
    'recheck uses modified image and caption and resets decisions',
    () async {
      controller.setCaption('連絡先 taro@example.com');
      await controller.loadPhoto(Uint8List.fromList([1]));
      await controller.runCheck([]);
      for (final finding in controller.findings) {
        await controller.decide(finding, ReviewDecision.hide);
      }
      await controller.applyAndRecheck([]);
      expect(controller.photo!.bytes, [9]);
      expect(controller.caption, '連絡先 ［非表示］');
      expect(controller.decisions, isEmpty);
      expect(controller.manualRegions, isEmpty);
    },
  );
}
