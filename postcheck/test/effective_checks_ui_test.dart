import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postcheck/domain/preferences.dart';
import 'package:postcheck/presentation/apple_components.dart';
import 'package:postcheck/presentation/nearby_card.dart';
import 'package:postcheck/presentation/nearby_controller.dart';
import 'package:postcheck/presentation/venue_check_status.dart';
import 'package:postcheck_rules/postcheck_rules.dart';
import 'nearby_controller_test.dart' show Repository, GPS;
import 'localization_test.dart' show localizedApp;

PublishedVenue venue({DateTime? until}) => PublishedVenue(
  id: 'fiction',
  version: 1,
  updatedAt: DateTime.utc(2026),
  policy: VenuePolicy(
    name: '架空施設',
    checkTargets: ['whiteboard', 'face'],
    validUntil: until,
  ),
);

void main() {
  for (final user in [false, true]) {
    for (final facility in [false, true]) {
      test(
        'all 12 targets use the same user $user OR venue $facility result',
        () {
          for (final target in CheckTarget.values) {
            final p = ReviewPreferences(disabledTargets: {if (!user) target});
            expect(
              p.effectiveEnabled(
                target,
                venueTargets: [if (facility) target.name],
              ),
              user || facility,
            );
          }
        },
      );
    }
  }
  for (final code in ['ja', 'en']) {
    testWidgets(
      '$code shows user, facility and result at 320px and 1.4 scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.4;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final prefs = ReviewPreferences(
          disabledTargets: CheckTarget.values
              .where((c) => c != CheckTarget.contact)
              .toSet(),
        );
        await tester.pumpWidget(
          localizedApp(
            Scaffold(
              body: ListView(
                children: [
                  VenueCheckStatus(
                    venue: venue(),
                    applied: true,
                    preferences: prefs,
                    aiEnabled: false,
                  ),
                ],
              ),
            ),
            code,
          ),
        );
        for (final target in CheckTarget.values) {
          final finder = find.byKey(ValueKey('effective-check-${target.name}'));
          await tester.scrollUntilVisible(finder, 100);
          final row = tester.widget<AppleRow>(finder);
          expect(
            row.value,
            [
                  CheckTarget.contact,
                  CheckTarget.face,
                  CheckTarget.whiteboard,
                ].contains(target)
                ? 'オン'
                : 'オフ',
          );
          if (target == CheckTarget.face) {
            expect(
              row.subtitle,
              code == 'ja' ? '利用者 オフ ／ 施設 オン' : 'You Off ／ Venue On',
            );
          }
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('expired facility contributes no targets', (tester) async {
    await tester.pumpWidget(
      localizedApp(
        Scaffold(
          body: ListView(
            children: [
              VenueCheckStatus(
                venue: venue(until: DateTime.utc(2020)),
                applied: true,
                preferences: ReviewPreferences(
                  disabledTargets: CheckTarget.values.toSet(),
                ),
              ),
            ],
          ),
        ),
        'ja',
      ),
    );
    expect(
      tester
          .widget<AppleRow>(find.byKey(const ValueKey('effective-check-face')))
          .value,
      'オフ',
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'open venue sheet immediately drops facility-only checks on OFF',
    (tester) async {
      final repo = Repository()..data = [venue()];
      final n = NearbyController(repository: repo, location: GPS());
      addTearDown(n.dispose);
      await n.refresh();
      n.choose(repo.data.single);
      final prefs = ReviewPreferences(
        disabledTargets: CheckTarget.values
            .where((c) => c != CheckTarget.contact)
            .toSet(),
      );
      await tester.pumpWidget(
        localizedApp(
          Scaffold(
            body: NearbyCard(
              controller: n,
              onChange: () {},
              preferences: prefs,
            ),
          ),
          'ja',
        ),
      );
      await tester.tap(find.text('架空施設'));
      await tester.pumpAndSettle();
      final face = find.byKey(const ValueKey('effective-check-face'));
      await tester.scrollUntilVisible(
        face,
        100,
        scrollable: find.byType(Scrollable).last,
      );
      expect(tester.widget<AppleRow>(face).value, 'オン');
      n.toggle(false);
      await tester.pumpAndSettle();
      expect(tester.widget<AppleRow>(face).value, 'オフ');
      expect(
        tester
            .widget<AppleRow>(
              find.byKey(const ValueKey('effective-check-contact')),
            )
            .value,
        'オン',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
