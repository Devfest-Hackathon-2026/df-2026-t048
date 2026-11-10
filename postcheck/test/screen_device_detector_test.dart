import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postcheck/adapters/screen_device_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('postcheck/screen_detector');

  test(
    'still-photo contour preserves four independent corners through padding',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => [
              [10, 10, 80, 80, 25, 15, 75, 20, 85, 80, 15, 75],
              [10, 10, 80, 80, -5, 15, 75, 20, 85, 80, 15, 75],
            ],
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final result = await ScreenDeviceDetector().inspectFile(
        'fixture',
        100,
        100,
      );
      expect(result.first.outline, hasLength(4));
      expect(result.first.padded(.012).outline!.first.x, .25);
      expect(result.first.outline![1].y, .2);
      expect(result.last.outline, isNull);
    },
  );

  test('keeps the native detector label for a whiteboard result', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => [
            {
              'box': [10, 20, 50, 40],
              'label': 'whiteboard',
            },
          ],
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final result = await ScreenDeviceDetector().inspectFile(
      'fixture',
      100,
      100,
    );
    expect(result.single.detectionLabel, 'whiteboard');
  });

  testWidgets('a native call that never returns cannot stall photo review', (
    tester,
  ) async {
    final native = Completer<Object?>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) => native.future);
    addTearDown(() {
      native.complete(<Object?>[]);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final response = ScreenDeviceDetector().inspectFile('test', 100, 100);
    final assertion = expectLater(response, throwsA(isA<TimeoutException>()));
    await tester.pump(const Duration(seconds: 4));
    await assertion;
  });

  test('normalizes, clips and rejects invalid detector boxes', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => [
            [10.0, 20.0, 50.0, 40.0],
            [-10.0, 10.0, 20.0, 20.0],
            [20.0, 20.0, -1.0, 4.0],
          ],
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final regions = await ScreenDeviceDetector().inspectFile('test', 100, 100);
    expect(regions, hasLength(2));
    expect(regions.first.x, closeTo(.1, .0001));
    expect(regions.first.width, closeTo(.5, .0001));
    expect(regions.last.x, 0);
    expect(regions.last.width, closeTo(.1, .0001));
  });

  testWidgets(
    'progressive owner can keep a native call alive beyond four seconds',
    (tester) async {
      final native = Completer<Object?>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) => native.future);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      var completed = false;
      final response = const ScreenDeviceDetector(timeout: null)
          .inspectFile('fictional', 100, 100)
          .then((value) {
            completed = true;
            return value;
          });
      await tester.pump(const Duration(seconds: 5));
      expect(completed, isFalse);
      native.complete(<Object?>[]);
      await tester.pump();
      expect(await response, isEmpty);
    },
  );

  test('Android frames are normalized in the upright, mirrored frame', () async {
    MethodCall? sent;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          sent = call;
          // Native returns boxes in the upright 480x640 frame.
          return [
            [48.0, 64.0, 96.0, 128.0],
          ];
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final bytes = Uint8List(640 * 480 * 3 ~/ 2);
    final plain = await ScreenDeviceDetector().inspectFrame(
      bytes, 640, 480, 640, rotation: 90,
    );
    expect((sent!.arguments as Map)['rotation'], 90);
    expect(plain.single.x, closeTo(.1, 1e-9));
    expect(plain.single.y, closeTo(.1, 1e-9));
    expect(plain.single.width, closeTo(.2, 1e-9));
    expect(plain.single.height, closeTo(.2, 1e-9));
    final mirrored = await ScreenDeviceDetector().inspectFrame(
      bytes, 640, 480, 640, rotation: 90, mirror: true,
    );
    expect(mirrored.single.x, closeTo(.7, 1e-9));
    expect(mirrored.single.y, closeTo(.1, 1e-9));
  });
}
