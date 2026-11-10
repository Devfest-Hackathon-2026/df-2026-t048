import 'package:postcheck_rules/contracts.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:postcheck/application/check_draft.dart';
import 'package:postcheck/domain/models.dart';
import 'package:postcheck/domain/ports.dart';
import 'package:postcheck/presentation/postcheck_controller.dart';
import 'controller_test.dart';

class WaitingPerception implements PerceptionPort {
  final pending = Completer<Observations>();
  @override
  Future<Observations> inspect(PhotoInput p) => pending.future;
}

class CountingContext implements ContextAnalysisPort {
  int calls = 0;
  @override
  Future<ContextResult> analyze(
    DraftInput d,
    Observations o, {
    PublishedVenue? venue,
  }) async {
    calls++;
    return const ContextResult(status: 'test');
  }
}

void main() {
  test('cancelled OCR cannot launch AI or replace a newer draft', () async {
    final perception = WaitingPerception(), context = CountingContext();
    final c = PostCheckController(
      check: CheckDraft(perception: perception, context: context),
      images: TestImages(),
      exporter: TestExport(),
    );
    addTearDown(c.dispose);
    await c.loadPhoto(Uint8List.fromList([1]));
    final pending = c.runCheck([]);
    c.cancelCheck();
    c.removePhoto();
    c.setCaption('新しい下書き');
    await c.runCheck([]);
    final current = c.report;
    perception.pending.complete(const Observations());
    await pending;
    expect(c.report, same(current));
    expect(c.caption, '新しい下書き');
    expect(context.calls, 1);
    expect(c.busy, isFalse);
  });
  test(
    'caption edit preserves image masks and requires new analysis',
    () async {
      final c = PostCheckController(
        check: CheckDraft(perception: TestPerception(), context: TestContext()),
        images: TestImages(),
        exporter: TestExport(),
      );
      addTearDown(c.dispose);
      await c.loadPhoto(Uint8List.fromList([1]));
      await c.runCheck([]);
      await c.decide(c.findings.single, ReviewDecision.hide);
      await c.reviseCaption('新しい説明');
      expect(c.photo!.bytes, [9]);
      expect(c.report, isNull);
      expect(c.canExport, isFalse);
      await c.restoreOriginal();
      expect(c.photo!.bytes, [1]);
      expect(c.caption, '');
    },
  );
}
