import 'dart:async';
import 'dart:typed_data';

import '../domain/models.dart';
import 'screen_device_detector.dart';

/// A timed-out platform call still owns its native work. Keep it in flight so
/// retries cannot queue more camera frames behind it or show its stale boxes.
final class LiveDeviceDetector {
  LiveDeviceDetector({
    this.timeout = const Duration(seconds: 4),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration timeout;
  final DateTime Function() _now;
  final _detector = const ScreenDeviceDetector(timeout: null);
  Future<List<ImageRegion>>? _pending;
  DateTime? _retryAt;
  int _failures = 0;
  bool unavailable = false;

  /// A camera reopen may retry immediately, but never overlap native calls.
  void retry() => _retryAt = null;

  Future<List<ImageRegion>> inspectFrame(
    Uint8List bytes,
    int width,
    int height,
    int bytesPerRow, {
    int rotation = 0,
    bool mirror = false,
  }) async {
    if (_pending != null || (_retryAt != null && _now().isBefore(_retryAt!))) {
      return const [];
    }
    final pending = _detector.inspectFrame(
      bytes,
      width,
      height,
      bytesPerRow,
      rotation: rotation,
      mirror: mirror,
    );
    _pending = pending;
    // Also observe completion after the UI timeout. Late boxes are discarded;
    // only availability is recovered before the next fresh camera frame.
    unawaited(
      pending.then<void>(
        (_) {
          _pending = null;
          _failures = 0;
          _retryAt = null;
          unavailable = false;
        },
        onError: (Object error, StackTrace stack) {
          _pending = null;
          unavailable = true;
          _failures = (_failures + 1).clamp(1, 5);
          _retryAt = _now().add(
            Duration(seconds: (1 << _failures).clamp(2, 30)),
          );
        },
      ),
    );
    try {
      return await pending.timeout(timeout);
    } on TimeoutException {
      unavailable = true;
      rethrow;
    }
  }
}
