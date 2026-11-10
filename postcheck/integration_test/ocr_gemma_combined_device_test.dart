import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:postcheck/adapters/downloaded_gemma.dart';
import 'package:postcheck/adapters/demo_input.dart';
import 'package:postcheck/adapters/image_processing.dart';
import 'package:postcheck/adapters/local_gemma.dart';
import 'package:postcheck/adapters/mlkit_perception.dart';
import 'package:postcheck/application/analysis_gate.dart';
import 'package:postcheck/application/check_draft.dart';
import 'package:postcheck/domain/models.dart';
import 'package:postcheck/adapters/local_storage.dart' show prepareLocalPrivacy;

/// Four-condition smoke test using only a generated fictional fixture.
/// It measures execution, not semantic precision or general OCR accuracy.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'four OCR/Gemma conditions run locally with grounded review targets',
    (tester) async {
      await prepareLocalPrivacy();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('PostCheck analysis verification')),
        ),
      );
      final fixture = await createDemoPhoto();
      expect(fixture, isNotNull);
      final photo = await const RasterImageAdapter().prepare(
        fixture!.buffer.asUint8List(),
      );
      final model = await DownloadedGemma().path();
      expect(
        model,
        isNotNull,
        reason: 'Downloaded vision model must be prepared on device',
      );
      final aggregates = <Map<String, Object>>[];
      for (final (name, enhanced, tuned) in [
        ('A', false, false),
        ('B', true, false),
        ('C', false, true),
        ('D', true, true),
      ]) {
        var basicMs = 0;
        final watch = Stopwatch()..start();
        final report =
            await CheckDraft(
              perception: MlKitPerceptionAdapter(enhanced: enhanced),
              context: LocalGemmaAdapter(modelPath: model, tuned: tuned),
            )(
              DraftInput(
                caption: '架空の新企画。連絡先 fixture@example.com',
                photo: photo,
              ),
              privateWords: ['新企画'],
              onCanFinish: () {
                if (basicMs == 0) basicMs = watch.elapsedMilliseconds;
              },
            );
        expect(
          report.findings.any(
            (f) =>
                f.target is PhotoTarget &&
                f.evidence.any((e) => e.kind == FindingKind.contact),
          ),
          isTrue,
        );
        for (final f in report.findings) {
          if (f.target case PhotoTarget(region: final region)) {
            expect(region.isValid, isTrue);
          }
          if (f.target case CaptionTarget(range: final range)) {
            expect(range.validFor('架空の新企画。連絡先 fixture@example.com'), isTrue);
          }
        }
        expect(
          report.aiStatus,
          contains('Gemmaが端末内'),
          reason:
              'Model must actually run; basic fallback is not a model success',
        );
        expect(
          AnalysisGate.shared.busy,
          isFalse,
          reason: 'Native resources must be released',
        );
        aggregates.add({
          'condition': name,
          'basicMs': basicMs,
          'totalMs': watch.elapsedMilliseconds,
          'reviewItems': report.findings.length,
          'photoContactItems': report.findings
              .where(
                (f) =>
                    f.target is PhotoTarget &&
                    f.evidence.any((e) => e.kind == FindingKind.contact),
              )
              .length,
          'aiEvidenceCount': report.findings
              .expand((f) => f.evidence)
              .where((f) => f.source == FindingSource.gemma)
              .length,
          'noteCount': report.notes.length,
        });
      }
      binding.reportData = {'fictionalFixtureSmoke': aggregates};
      // Aggregate counts/durations only. Never log inspected content or AI output.
      debugPrint('POSTCHECK_ANALYSIS_AGGREGATES ${jsonEncode(aggregates)}');
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
