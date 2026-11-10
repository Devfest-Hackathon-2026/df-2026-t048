import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../adapters/screen_device_detector.dart';

/// Dedicated release-build probe. Only generated blank pixels are inspected;
/// output contains statuses and timing, never user images, text or SDK errors.
Future<void> runDetectorInitializationSmokeTest() async {
  final results = <String, Object?>{'schema': 1};
  final folder = await Directory(
    '${(await getTemporaryDirectory()).path}/detector-smoke',
  ).create();
  const width = 640, height = 480;
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(128, 128, 128));
  final file = File('${folder.path}/blank.png');
  try {
    await file.writeAsBytes(img.encodePng(image));
    final detector = ScreenDeviceDetector(timeout: const Duration(seconds: 30));
    final watch = Stopwatch()..start();
    await detector.inspectFile(file.path, width, height);
    results['fileSucceeded'] = true;
    results['fileMs'] = watch.elapsedMilliseconds;
    for (final rotation in [0, 90, 270]) {
      watch.reset();
      final pixels = Platform.isAndroid
          ? (Uint8List(width * height * 3 ~/ 2)
              ..fillRange(0, width * height * 3 ~/ 2, 128))
          : image.getBytes(order: img.ChannelOrder.bgra);
      await detector.inspectFrame(
        pixels,
        width,
        height,
        Platform.isAndroid ? width : width * 4,
        rotation: Platform.isAndroid ? rotation : 0,
        mirror: rotation == 270,
      );
      results['frame${rotation}Succeeded'] = true;
      results['frame${rotation}Ms'] = watch.elapsedMilliseconds;
    }
    results['passed'] = true;
  } catch (_) {
    results['passed'] = false;
  } finally {
    if (await folder.exists()) await folder.delete(recursive: true);
  }
  // The caller is compile-time gated; the normal APK never runs this probe.
  debugPrint('POSTCHECK_DETECTOR_SMOKE ${jsonEncode(results)}');
}
