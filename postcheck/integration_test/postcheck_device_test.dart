import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:postcheck/adapters/demo_input.dart';
import 'package:postcheck/adapters/image_processing.dart';
import 'package:postcheck/adapters/local_gemma.dart';
import 'package:postcheck/adapters/local_storage.dart';
import 'package:postcheck/adapters/mlkit_perception.dart';
import 'package:postcheck/application/check_draft.dart';
import 'package:postcheck/domain/models.dart';
import 'package:postcheck/domain/ports.dart';
import 'package:postcheck/main.dart';
import 'package:postcheck/presentation/postcheck_controller.dart';

class CaptureExport implements ExportPort {
  ExportArtifact? captured;
  @override
  Future<void> share(
    ExportArtifact artifact, {
    double? anchorX,
    double? anchorY,
  }) async {
    captured = artifact;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real Japanese ML Kit OCR → review → burned-in export on iPhone',
    (tester) async {
      await prepareLocalPrivacy();
      final settings = LocalSettings(await SharedPreferences.getInstance());
      final output = CaptureExport();
      final controller = PostCheckController(
        check: CheckDraft(
          perception: MlKitPerceptionAdapter(),
          context: LocalGemmaAdapter(modelPath: null),
        ),
        images: const RasterImageAdapter(),
        exporter: output,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        PostCheckApp(controller: controller, settings: settings),
      );
      final fixture = await createDemoPhoto();
      expect(fixture, isNotNull);
      controller.setCaption('来月の新企画。連絡先 taro@example.com');
      await controller.loadPhoto(fixture!.buffer.asUint8List());
      await controller.runCheck([]);
      await tester.pumpAndSettle();
      expect(controller.report, isNotNull);
      expect(controller.report!.notes, isEmpty);
      expect(
        controller.findings.any(
          (f) => f.target is PhotoTarget && f.excerpt.contains('山田'),
        ),
        isTrue,
      );
      expect(
        controller.findings.any(
          (f) => f.target is PhotoTarget && f.excerpt.contains('新企画'),
        ),
        isTrue,
      );
      expect(
        controller.findings.any(
          (f) => f.target is PhotoTarget && f.excerpt.contains('example.com'),
        ),
        isTrue,
      );
      for (final finding in controller.findings) {
        await controller.decide(finding, ReviewDecision.hide);
      }
      expect(controller.canExport, isFalse);
      await controller.applyAndRecheck([]);
      for (final finding in controller.findings) {
        await controller.decide(finding, ReviewDecision.keep);
      }
      expect(controller.canExport, isTrue);
      await controller.share();
      expect(output.captured!.imageBytes, isNotNull);
      expect(output.captured!.caption.contains('taro@example.com'), isFalse);
      expect(
        controller.findings.any((f) => f.excerpt.contains('example.com')),
        isFalse,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
