// ignore: depend_on_referenced_packages
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postcheck/adapters/live_camera_page.dart';
import 'package:postcheck/l10n/app_localizations.dart';
import 'package:postcheck/presentation/nearby_card.dart';
import 'package:postcheck/presentation/nearby_controller.dart';

import 'camera_startup_test.dart' show EmptyLibrary;
import 'camera_zoom_test.dart' show ZoomCamera;
import 'localization_test.dart' show localizedApp;
import 'nearby_controller_test.dart' show Repository, GPS;

void main() {
  for (final language in ['ja', 'en']) {
    for (final width in [320.0, 390.0]) {
      testWidgets(
        'camera title is centered with location and flash ($language, $width)',
        (tester) async {
          tester.view.physicalSize = Size(width, 844);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = 1.4;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final previous = CameraPlatform.instance;
          CameraPlatform.instance = ZoomCamera();
          addTearDown(() => CameraPlatform.instance = previous);
          for (final name in [
            'google_mlkit_text_recognizer',
            'google_mlkit_face_detector',
          ]) {
            tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
              MethodChannel(name),
              (_) async => null,
            );
          }
          final nearby = NearbyController(
            repository: Repository(),
            location: GPS(),
          );
          addTearDown(nearby.dispose);
          await tester.pumpWidget(
            localizedApp(
              LiveCameraPage(
                privateWords: const [],
                library: EmptyLibrary(),
                nearby: nearby,
              ),
              language,
            ),
          );
          await tester.pumpAndSettle();
          final title = find.byKey(const ValueKey('camera-title'));
          expect(tester.getCenter(title).dx, closeTo(width / 2, .01));
          final s = AppStrings(Locale(language));
          final close = find.byTooltip(s.text('カメラを閉じる'));
          final flash = find.byTooltip(s.text('フラッシュ：オフ'));
          expect(close.hitTestable(), findsOneWidget);
          expect(flash.hitTestable(), findsOneWidget);
          expect(find.byType(NearbyCard).hitTestable(), findsOneWidget);
          expect(
            tester.getRect(close).right,
            lessThan(tester.getRect(title).left),
          );
          expect(
            tester.getRect(title).right,
            lessThan(tester.getRect(find.byType(NearbyCard)).left),
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        },
      );
    }
  }
}
