import 'dart:async';
// Platform fake exercises the real camera widget without camera hardware.
// ignore: depend_on_referenced_packages
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postcheck/adapters/live_camera_page.dart';
import 'camera_startup_test.dart' show EmptyLibrary;

class ZoomCamera extends CameraPlatform {
  final values = <double>[];
  int creates = 0;
  @override
  Future<List<CameraDescription>> availableCameras() async => [
    const CameraDescription(
      name: 'virtual',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
      lensType: CameraLensType.wide,
    ),
  ];
  @override
  Future<int> createCameraWithSettings(
    CameraDescription d,
    MediaSettings? settings,
  ) async => ++creates;
  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {}
  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int id) => Stream.value(
    CameraInitializedEvent(
      id,
      1920,
      1080,
      ExposureMode.auto,
      true,
      FocusMode.auto,
      true,
    ),
  );
  @override
  Stream<CameraErrorEvent> onCameraError(int id) =>
      StreamController<CameraErrorEvent>().stream;
  @override
  Stream<CameraClosingEvent> onCameraClosing(int id) =>
      StreamController<CameraClosingEvent>().stream;
  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      Stream.value(
        const DeviceOrientationChangedEvent(DeviceOrientation.portraitUp),
      );
  @override
  Future<void> lockCaptureOrientation(
    int id,
    DeviceOrientation orientation,
  ) async {}
  @override
  Future<void> setFlashMode(int id, FlashMode mode) async {}
  @override
  Future<double> getMinZoomLevel(int id) async => .5;
  @override
  Future<double> getMaxZoomLevel(int id) async => 10;
  @override
  Future<void> setZoomLevel(int id, double zoom) async {
    values.add(zoom);
  }

  @override
  Stream<CameraImageData> onStreamedFrameAvailable(
    int id, {
    CameraImageStreamOptions? options,
  }) => const Stream.empty();
  @override
  Widget buildPreview(int id) => const SizedBox.expand();
  @override
  Future<void> dispose(int id) async {}
}

void main() {
  testWidgets('2x returns to 1x and 0.5x without recreating camera', (
    tester,
  ) async {
    final previous = CameraPlatform.instance;
    final platform = ZoomCamera();
    CameraPlatform.instance = platform;
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
    await tester.pumpWidget(
      MaterialApp(
        home: LiveCameraPage(privateWords: const [], library: EmptyLibrary()),
      ),
    );
    await tester.pumpAndSettle();
    for (final target in [2.0, 1.0, .5, 2.0, .5]) {
      await tester.tap(
        find.text(target == .5 ? '0.5' : target.toInt().toString()),
      );
      for (var i = 0; i < 35; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(platform.values.last, closeTo(target, .001));
    }
    expect(platform.creates, 1);
    expect(platform.values.every((v) => v >= .5 && v <= 10), isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
