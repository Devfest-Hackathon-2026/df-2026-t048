import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../adapters/demo_input.dart';
import '../adapters/image_processing.dart';
import '../adapters/social_share.dart';
import '../adapters/story_image.dart';
import '../domain/social_share.dart';
import '../adapters/local_gemma.dart';
import '../adapters/local_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../adapters/mlkit_perception.dart';
import '../application/check_draft.dart';
import '../domain/models.dart';
import '../domain/ports.dart';
import '../presentation/postcheck_controller.dart';
import '../adapters/screen_device_detector.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

class _CaptureOutput implements ExportPort {
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

/// Only enabled in dedicated builds. Uses test fixtures, never the user's draft.
Future<void> runDeviceSmokeTest() async {
  if (const bool.fromEnvironment('POSTCHECK_DEVICE_DETECTOR_TEST')) {
    final result = <String, Object?>{};
    File? fixture;
    try {
      final data = await rootBundle.load(
        'assets/screen_detector/diagnostic.jpg',
      );
      final bytes = data.buffer.asUint8List();
      final decoded = img.decodeImage(bytes)!;
      final root = await getTemporaryDirectory();
      final file = File('${root.path}/postcheck-detector-diagnostic.jpg');
      fixture = file;
      await file.writeAsBytes(bytes);
      final detector = ScreenDeviceDetector();
      final clock = Stopwatch()..start();
      final image = await detector.inspectFile(
        file.path,
        decoded.width,
        decoded.height,
      );
      result['fileCount'] = image.length;
      result['fileMs'] = clock.elapsedMilliseconds;
      clock.reset();
      final bgra = decoded.getBytes(order: img.ChannelOrder.bgra);
      final frame = await detector.inspectFrame(
        bgra,
        decoded.width,
        decoded.height,
        decoded.width * 4,
      );
      result['frameCount'] = frame.length;
      result['frameMs'] = clock.elapsedMilliseconds;
    } catch (e) {
      result['error'] = e.toString();
    } finally {
      if (fixture != null && await fixture.exists()) await fixture.delete();
    }
    final root = await getApplicationDocumentsDirectory();
    await File(
      '${root.path}/postcheck-detector-diagnostic.json',
    ).writeAsString(jsonEncode(result));
    return;
  }
  final output = _CaptureOutput();
  final controller = PostCheckController(
    check: CheckDraft(
      perception: MlKitPerceptionAdapter(),
      context: LocalGemmaAdapter(modelPath: null),
    ),
    images: const RasterImageAdapter(),
    exporter: output,
    socialExporter: SocialShareAdapter(
      exporter: output,
      copyText: (_) async {},
    ),
  );
  final result = <String, Object?>{
    'startedAt': DateTime.now().toIso8601String(),
    'gemma': 'not tested: model not installed',
  };
  void verify(bool condition, String name) {
    result[name] = condition;
    if (!condition) {
      throw StateError(name);
    }
  }

  try {
    final fixture = await createDemoPhoto();
    verify(fixture != null, 'fixtureRendered');
    controller.setCaption('来月の新企画。連絡先 taro@example.com');
    await controller.loadPhoto(fixture!.buffer.asUint8List());
    verify(controller.photo != null, 'photoPrepared');
    await controller.runCheck([]);
    verify(
      controller.report != null && controller.report!.notes.isEmpty,
      'mlKitCompleted',
    );
    verify(
      controller.findings.any(
        (f) => f.target is PhotoTarget && f.excerpt.contains('山田'),
      ),
      'japaneseNameRecognized',
    );
    verify(
      controller.findings.any(
        (f) => f.target is PhotoTarget && f.excerpt.contains('新企画'),
      ),
      'japaneseScreenRecognized',
    );
    verify(
      controller.findings.any(
        (f) => f.target is PhotoTarget && f.excerpt.contains('example.com'),
      ),
      'imageEmailRecognized',
    );
    result['candidateCount'] = controller.findings.length;
    if (const bool.fromEnvironment('POSTCHECK_AI_SELF_TEST')) {
      final settings = LocalSettings(await SharedPreferences.getInstance());
      final model = await settings.modelPath();
      verify(model != null, 'gemmaModelPresent');
      final observations = await MlKitPerceptionAdapter().inspect(
        controller.photo!,
      );
      final ai = await LocalGemmaAdapter(modelPath: model).analyze(
        DraftInput(caption: controller.caption, photo: controller.photo),
        observations,
      );
      result['gemma'] = ai.status;
      result['gemmaCandidateCount'] = ai.findings.length;
      verify(ai.status.startsWith('Gemmaが'), 'gemmaInferenceCompleted');
    }
    for (final finding in controller.findings) {
      await controller.decide(finding, ReviewDecision.hide);
    }
    verify(!controller.canExport, 'editedContentRequiresRecheck');
    await controller.applyAndRecheck([]);
    for (final finding in controller.findings) {
      await controller.decide(finding, ReviewDecision.keep);
    }
    verify(controller.canExport, 'allCandidatesReviewed');
    await controller.share();
    verify(
      output.artifact?.imageBytes != null &&
          !output.artifact!.caption.contains('example.com'),
      'redactedExportCreated',
    );
    verify(
      controller.report != null &&
          controller.report!.notes.isEmpty &&
          !controller.findings.any((f) => f.excerpt.contains('example.com')),
      'redactedImageRechecked',
    );
    final png = await const StoryImageComposer().compose(
      output.artifact!,
      StoryLayout.card,
    );
    final story = img.decodePng(png);
    verify(
      story != null &&
          story.width == 1080 &&
          story.height == 1920 &&
          story.exif.isEmpty,
      'storyImagePrepared',
    );
    // Exercise the social path with a recording output, without opening an SNS
    // or transmitting any synthetic content to another service.
    await controller.shareTo(ShareDestination.instagramPost);
    verify(
      output.artifact?.imageBytes != null &&
          !output.artifact!.caption.contains('example.com'),
      'socialHandoffPrepared',
    );
    result['passed'] = true;
  } catch (_) {
    result['passed'] = false;
  } finally {
    controller.dispose();
    result['completedAt'] = DateTime.now().toIso8601String();
    final root = await getApplicationDocumentsDirectory();
    await File('${root.path}/postcheck-device-verification.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(result),
      flush: true,
    );
  }
}
