import 'package:flutter/services.dart';

import '../domain/models.dart';

/// Native on-device object detector. Coordinates are normalized in Dart.
final class ScreenDeviceDetector {
  const ScreenDeviceDetector({this.timeout = const Duration(seconds: 4)});

  /// A progressive scan owns its pending native call beyond the UI deadline.
  final Duration? timeout;
  static const _channel = MethodChannel('postcheck/screen_detector');

  Future<List<ImageRegion>> inspectFile(String path, int width, int height) =>
      _detect('file', {'path': path}, width, height);

  /// iOS passes upright BGRA frames. Android passes sensor-oriented NV21
  /// frames with the clockwise [rotation] that makes them upright; boxes come
  /// back in the upright frame and are mirrored when [mirror] is set.
  Future<List<ImageRegion>> inspectFrame(
    Uint8List bytes,
    int width,
    int height,
    int bytesPerRow, {
    int rotation = 0,
    bool mirror = false,
  }) {
    final swap = rotation % 180 != 0;
    return _detect(
      'frame',
      {
        'bytes': bytes,
        'width': width,
        'height': height,
        'bytesPerRow': bytesPerRow,
        'rotation': rotation,
      },
      swap ? height : width,
      swap ? width : height,
      mirror: mirror,
    );
  }

  Future<List<ImageRegion>> _detect(
    String method,
    Map<String, Object> args,
    int width,
    int height, {
    bool mirror = false,
  }) async {
    // Use invokeMethod so each result can be either the legacy coordinate list
    // or a labeled `{box, label}` map from the native detector.
    final pending = _channel.invokeMethod<List<Object?>>(method, args);
    final result = timeout == null
        ? await pending
        : await pending.timeout(timeout!);
    final regions = <ImageRegion>[];
    for (final raw in result ?? <Object?>[]) {
      final (box, label) = _decodeDetection(raw);
      if (box == null || (box.length != 4 && box.length != 12)) {
        continue;
      }
      final left = (box[0] as num).toDouble();
      final region = ImageRegion.fromPixels(
        mirror ? width - left - (box[2] as num).toDouble() : left,
        (box[1] as num).toDouble(),
        (box[2] as num).toDouble(),
        (box[3] as num).toDouble(),
        width,
        height,
      );
      if (region != null) {
        List<MaskPoint>? outline;
        if (box.length == 12) {
          final points = [
            for (var i = 4; i < 12; i += 2)
              MaskPoint(
                (box[i] as num).toDouble() / width,
                (box[i + 1] as num).toDouble() / height,
              ),
          ];
          if (MaskOperation(MaskOperationKind.polygon, points).isValid) {
            outline = points;
          }
        }
        regions.add(
          ImageRegion(
            region.x,
            region.y,
            region.width,
            region.height,
            outline: outline,
            detectionLabel: label,
          ),
        );
      }
    }
    return regions;
  }

  (List<Object?>?, String?) _decodeDetection(Object? raw) {
    if (raw is Map) {
      final box = raw['box'];
      final label = raw['label'];
      if (box is List &&
          box.every((value) => value is num) &&
          (label == null || label is String)) {
        return (List<Object?>.from(box), label as String?);
      }
      return (null, null);
    }
    if (raw is List && raw.every((value) => value is num)) {
      return (List<Object?>.from(raw), null);
    }
    return (null, null);
  }
}
