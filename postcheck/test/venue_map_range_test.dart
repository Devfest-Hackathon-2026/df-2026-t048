import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:postcheck/application/nearby_rules.dart';
import 'package:postcheck/domain/location.dart';
import 'package:postcheck/l10n/app_localizations.dart';
import 'package:postcheck/presentation/app_theme.dart';
import 'package:postcheck/presentation/nearby_controller.dart';
import 'package:postcheck/presentation/venue_page.dart';
import 'nearby_controller_test.dart' show Repository, GPS;
import 'nearby_rules_test.dart' show fixture;

// Inspect the real GoogleMap widget's overlays without loading native map tiles.
class _MapPlatform extends GoogleMapsFlutterPlatform {
  @override
  Widget buildViewWithConfiguration(
    int creationId,
    PlatformViewCreatedCallback onPlatformViewCreated, {
    required MapWidgetConfiguration widgetConfiguration,
    MapConfiguration mapConfiguration = const MapConfiguration(),
    MapObjects mapObjects = const MapObjects(),
  }) => const SizedBox.expand();
}

void main() {
  late GoogleMapsFlutterPlatform original;
  setUp(() {
    original = GoogleMapsFlutterPlatform.instance;
    GoogleMapsFlutterPlatform.instance = _MapPlatform();
  });
  tearDown(() => GoogleMapsFlutterPlatform.instance = original);

  for (final language in ['ja', 'en']) {
    testWidgets(
      '500m overlays and current range update in $language at 320px',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.4;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        var now = DateTime.now();
        final repo = Repository()
          ..data = [
            fixture('a'),
            fixture('b', lat: 35.02),
            fixture('expired', until: now),
            fixture('private', visibility: 'organization'),
          ];
        final nearby = NearbyController(
          repository: repo,
          location: GPS(),
          rules: NearbyRules(now: () => now),
        );
        addTearDown(nearby.dispose);
        await nearby.refresh();
        nearby.rules.observe(LocationFix(35.00449, 139, 5, now)); // ~499m.
        await tester.pumpWidget(
          MaterialApp(
            theme: buildPostCheckTheme(),
            locale: Locale(language),
            supportedLocales: AppStrings.supportedLocales,
            localizationsDelegates: const [
              AppStrings.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            home: VenuePage(repository: repo, nearby: nearby, mapEnabled: true),
          ),
        );
        await tester.pumpAndSettle();
        GoogleMap map() => tester.widget<GoogleMap>(find.byType(GoogleMap));
        Set<Circle> ranges() => map().circles
            .where((c) => c.circleId.value.startsWith('venue-range-'))
            .toSet();
        expect(ranges().map((c) => c.circleId.value), {
          'venue-range-a',
          'venue-range-b',
        });
        for (final circle in ranges()) {
          expect(circle.radius, 500);
          expect(circle.fillColor.b, greaterThan(circle.fillColor.r));
          expect(circle.fillColor.a, allOf(greaterThan(0), lessThan(.3)));
        }
        expect(
          ranges()
              .firstWhere((c) => c.circleId.value == 'venue-range-a')
              .center,
          const LatLng(35, 139),
        );
        expect(
          map().circles.any((c) => c.circleId.value == 'location-accuracy'),
          true,
        );
        final strings = AppStrings(Locale(language));
        expect(find.text(strings.text('自動選択の範囲内（推定）')), findsOneWidget);
        expect(find.text(strings.text('水色の円：自動選択の範囲（半径500m）')), findsOneWidget);
        nearby.toggle(false);
        await tester.pumpAndSettle();
        expect(ranges().every((c) => c.strokeWidth == 2), true);
        expect(find.text(strings.text('自動選択の範囲内（推定）')), findsOneWidget);

        now = now.add(const Duration(seconds: 1));
        nearby.rules.observe(LocationFix(35.00451, 139, 5, now)); // ~501m.
        await nearby.refresh();
        await tester.pumpAndSettle();
        expect(find.text(strings.text('自動選択の範囲外（推定）')), findsOneWidget);
        expect(ranges(), hasLength(2));

        now = now.add(const Duration(seconds: 1));
        nearby.rules.observe(LocationFix(35, 139, 200, now));
        await nearby.refresh();
        await tester.pumpAndSettle();
        expect(find.text(strings.text('精度不足のため範囲判定を保留中')), findsOneWidget);

        now = now.add(const Duration(seconds: 61));
        await nearby.refresh();
        await tester.pumpAndSettle();
        expect(find.text(strings.text('現在地を未取得')), findsOneWidget);
        expect(
          map().circles.any((c) => c.circleId.value == 'location-accuracy'),
          false,
        );

        repo.data = [];
        await tester.tap(find.byTooltip(strings.text('再読込')));
        await tester.pumpAndSettle();
        expect(ranges(), isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
