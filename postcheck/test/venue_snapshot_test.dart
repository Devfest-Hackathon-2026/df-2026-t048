import 'package:postcheck_rules/contracts.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:postcheck/application/check_draft.dart';
import 'package:postcheck/application/nearby_rules.dart';
import 'package:postcheck/domain/location.dart';
import 'package:postcheck/domain/models.dart';
import 'package:postcheck/domain/ports.dart';
import 'package:postcheck/presentation/postcheck_controller.dart';
import 'controller_test.dart'
    show TestPerception, TestContext, TestImages, TestExport;
import 'nearby_rules_test.dart' show fixture;

class DelayedContext implements ContextAnalysisPort {
  final pending = Completer<ContextResult>();
  @override
  Future<ContextResult> analyze(
    DraftInput draft,
    Observations observations, {
    PublishedVenue? venue,
  }) => pending.future;
}

void main() {
  PostCheckController controller([ContextAnalysisPort? ai]) =>
      PostCheckController(
        check: CheckDraft(
          perception: TestPerception(),
          context: ai ?? TestContext(),
        ),
        images: TestImages(),
        exporter: TestExport(),
      );
  test(
    'captured venue stays A when foreground candidate moves to B; OFF retains basic contact check',
    () async {
      final c = controller();
      addTearDown(c.dispose);
      var now = DateTime.utc(2026, 11, 8);
      final nearby = NearbyRules(now: () => now)
        ..replaceCatalog([fixture('a'), fixture('b', lat: 35.002)]);
      nearby.choose(fixture('a'));
      c.selectVenue(nearby.active);
      c.setCaption('試作A taro@example.com');
      nearby.automatic();
      for (var i = 0; i < 2; i++) {
        now = now.add(const Duration(seconds: 15));
        nearby.observe(LocationFix(35.002, 139, 5, now));
      }
      expect(nearby.active?.id, 'b');
      expect(c.venue?.id, 'a');
      await c.runCheck([]);
      expect(c.findings.any((f) => f.ruleEvidence != null), true);
      c.selectVenue(null);
      await c.runCheck([]);
      expect(c.findings.any((f) => f.kind == FindingKind.contact), true);
      expect(c.findings.any((f) => f.ruleEvidence != null), false);
    },
  );
  test(
    'revocation during asynchronous checking discards the old result',
    () async {
      final ai = DelayedContext();
      final c = controller(ai);
      addTearDown(c.dispose);
      c.selectVenue(fixture('a'));
      c.setCaption('試作A');
      final check = c.runCheck([]);
      c.reconcileVenue([]);
      ai.pending.complete(const ContextResult(status: 'test', findings: []));
      await check;
      expect(c.venue, isNull);
      expect(c.report, isNull);
      expect(c.canExport, false);
    },
  );
  test(
    'new version invalidates previous check and requires review again',
    () async {
      final c = controller();
      addTearDown(c.dispose);
      c.selectVenue(fixture('a'));
      c.setCaption('試作A');
      await c.runCheck([]);
      c.reconcileVenue([fixture('a', version: 2)]);
      expect(c.venue?.version, 2);
      expect(c.report, isNull);
      expect(c.canExport, false);
    },
  );
}
