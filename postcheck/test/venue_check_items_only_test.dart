import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postcheck/application/check_draft.dart';
import 'package:postcheck/domain/models.dart';
import 'package:postcheck/domain/preferences.dart';
import 'package:postcheck/l10n/app_localizations.dart';
import 'package:postcheck_rules/postcheck_rules.dart';
import 'controller_test.dart' show TestPerception, TestContext;
import 'venue_multilingual_test.dart' show screen;

void main() {
  const policy = VenuePolicy(
    name: 'Fictional check-item venue',
    checkTargets: ['whiteboard', 'poster'],
  );
  test('admin/API check IDs and labels exactly match the app settings', () {
    expect(CheckTarget.values.map((v) => v.name), venueCheckTargets);
    expect({
      for (final v in CheckTarget.values) v.name: v.label,
    }, venueCheckTargetLabels);
    final received = VenuePolicy.fromJson(policy.toJson());
    expect(received.hasLegacyRuleDetails, false);
    const finding = Finding(
      id: 'whiteboard',
      kind: FindingKind.screenDevice,
      question: 'q',
      target: PhotoTarget(ImageRegion(.1, .1, .2, .2)),
      source: FindingSource.deviceModel,
      detectedLabel: 'whiteboard',
    );
    final prefs = ReviewPreferences(
      disabledTargets: CheckTarget.values.toSet(),
    );
    expect(prefs.shows(finding), false);
    expect(prefs.shows(finding, venueTargets: received.checkTargets), true);
  });

  test(
    'check-only policies need no semantic review of missing original text',
    () async {
      final report =
          await CheckDraft(
            perception: TestPerception(),
            context: TestContext(),
          )(
            const DraftInput(caption: 'Fictional test caption'),
            venue: PublishedVenue(
              id: 'fiction',
              version: 1,
              updatedAt: DateTime.now(),
              policy: policy,
            ),
          );
      expect(report.notes.any((v) => v.contains('施設が指定した確認項目')), true);
      expect(
        report.notes.any((v) => v.contains('原文') || v.contains('施設のSNS公開条件')),
        false,
      );
    },
  );

  for (final code in ['ja', 'en']) {
    testWidgets('check-only venue shows selected items in $code at 320px', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(screen(policy, code));
      await tester.pumpAndSettle();
      final strings = AppStrings(Locale(code));
      expect(find.text(strings.text('この施設で必ず指摘する項目')), findsOneWidget);
      expect(find.text(strings.text('ホワイトボード')), findsOneWidget);
      expect(find.text(strings.text('ポスター')), findsOneWidget);
      expect(find.text(strings.text('原文の言語')), findsNothing);
      expect(find.text(strings.text('ルールの原文')), findsNothing);
      expect(find.text(strings.text('商用利用')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
