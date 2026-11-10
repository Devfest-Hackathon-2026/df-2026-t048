import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postcheck/adapters/live_device_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('postcheck/screen_detector');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final bytes = Uint8List(640 * 480 * 3 ~/ 2);
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets(
    'late native completion cannot queue frames or display stale boxes',
    (tester) async {
      final first = Completer<Object?>();
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (_) async {
        calls++;
        if (calls == 1) return first.future;
        return [
          [64, 48, 128, 96],
        ];
      });
      final detector = LiveDeviceDetector();
      final result = detector.inspectFrame(bytes, 640, 480, 640);
      final check = expectLater(result, throwsA(isA<TimeoutException>()));
      await tester.pump(const Duration(seconds: 5));
      await check;
      expect(detector.unavailable, isTrue);
      expect(await detector.inspectFrame(bytes, 640, 480, 640), isEmpty);
      detector.retry();
      expect(await detector.inspectFrame(bytes, 640, 480, 640), isEmpty);
      expect(calls, 1);
      first.complete([
        [320, 240, 64, 48],
      ]);
      await tester.pump();
      expect(detector.unavailable, isFalse);
      final fresh = await detector.inspectFrame(bytes, 640, 480, 640);
      expect(calls, 2);
      expect(fresh.single.x, .1);
    },
  );

  test('platform failure recovers after cooldown with a fresh frame', () async {
    var now = DateTime.utc(2026, 11, 10);
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      if (++calls == 1) throw PlatformException(code: 'detector_unavailable');
      return <Object?>[];
    });
    final detector = LiveDeviceDetector(now: () => now);
    await expectLater(
      detector.inspectFrame(bytes, 640, 480, 640),
      throwsA(isA<PlatformException>()),
    );
    expect(detector.unavailable, isTrue);
    expect(await detector.inspectFrame(bytes, 640, 480, 640), isEmpty);
    expect(calls, 1);
    now = now.add(const Duration(seconds: 2));
    expect(await detector.inspectFrame(bytes, 640, 480, 640), isEmpty);
    expect(calls, 2);
    expect(detector.unavailable, isFalse);
  });

  testWidgets(
    'late native error is observed and can retry without an unhandled error',
    (tester) async {
      final native = Completer<Object?>();
      var calls = 0;
      var now = DateTime.utc(2026, 11, 10);
      messenger.setMockMethodCallHandler(channel, (_) async {
        calls++;
        if (calls == 1) return await native.future;
        return <Object?>[];
      });
      final detector = LiveDeviceDetector(now: () => now);
      final check = expectLater(
        detector.inspectFrame(bytes, 640, 480, 640),
        throwsA(isA<TimeoutException>()),
      );
      await tester.pump(const Duration(seconds: 5));
      await check;
      native.completeError(PlatformException(code: 'detector_unavailable'));
      await tester.pump();
      expect(detector.unavailable, isTrue);
      detector.retry();
      expect(await detector.inspectFrame(bytes, 640, 480, 640), isEmpty);
      expect(calls, 2);
      expect(detector.unavailable, isFalse);
    },
  );
}
