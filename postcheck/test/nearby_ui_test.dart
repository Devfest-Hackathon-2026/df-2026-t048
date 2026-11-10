import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postcheck/presentation/nearby_card.dart';
import 'package:postcheck/presentation/nearby_controller.dart';
import 'package:postcheck/presentation/app_theme.dart';
import 'nearby_controller_test.dart' show Repository, GPS;

void main() {
  testWidgets('camera location icon opens rules without taking a text row', (
    tester,
  ) async {
    final n = NearbyController(
      repository: Repository(),
      location: GPS(),
      demo: true,
    );
    addTearDown(n.dispose);
    await n.refresh();
    await n.simulate();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPostCheckTheme(),
        home: Scaffold(
          body: Center(
            child: NearbyCard(
              controller: n,
              onChange: () {},
              compact: true,
              iconOnly: true,
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(NearbyCard)), const Size(44, 44));
    expect(find.byType(Text), findsNothing);
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    expect(find.byType(Switch), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(n.active, isNull);
  });
  for (final compact in [false, true]) {
    testWidgets(
      'venue ON/OFF keeps basic-check label at 320px, compact=$compact',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.4;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final n = NearbyController(
          repository: Repository(),
          location: GPS(),
          demo: true,
        );
        addTearDown(n.dispose);
        await n.refresh();
        await n.simulate();
        await tester.pumpWidget(
          MaterialApp(
            theme: buildPostCheckTheme(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: NearbyCard(
                  controller: n,
                  onChange: () {},
                  compact: compact,
                ),
              ),
            ),
          ),
        );
        if (compact) {
          expect(tester.getSize(find.byType(NearbyCard)).height, 44);
          expect(find.text('ON'), findsOneWidget);
          await tester.tap(find.byType(NearbyCard));
          await tester.pumpAndSettle();
          expect(find.textContaining('利用者がONにした項目はチェックします'), findsOneWidget);
        } else {
          expect(find.textContaining('ON ·'), findsOneWidget);
        }
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
        expect(n.active, isNull);
        if (!compact) {
          expect(find.textContaining('OFF · 基本チェック'), findsOneWidget);
        }
        await n.simulate(outside: true);
        await n.simulate();
        await tester.pumpAndSettle();
        expect(n.active, isNull);
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
        expect(n.active, isNotNull);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
