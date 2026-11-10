import 'dart:typed_data';
import 'dart:math' as math;
import 'package:postcheck_rules/contracts.dart';

final class LocationFix {
  const LocationFix(this.latitude, this.longitude, this.accuracy, this.at);
  final double latitude, longitude, accuracy;
  final DateTime at;
  bool displayableAt(DateTime now) =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude.abs() <= 90 &&
      longitude.abs() <= 180 &&
      accuracy.isFinite &&
      accuracy >= 0 &&
      !at.isAfter(now.add(const Duration(seconds: 5))) &&
      now.difference(at) <= const Duration(seconds: 60);
  bool usableAt(DateTime now) => displayableAt(now) && accuracy <= 50;

  double distanceTo(LocationFix other) {
    const r = math.pi / 180;
    final h =
        math.pow(math.sin((other.latitude - latitude) * r / 2), 2) +
        math.cos(latitude * r) *
            math.cos(other.latitude * r) *
            math.pow(math.sin((other.longitude - longitude) * r / 2), 2);
    return 6371000 * 2 * math.asin(math.sqrt(h.clamp(0, 1)));
  }
}

abstract interface class LocationPort {
  Future<bool> permitted();
  Future<LocationFix> locate({bool requestPermission = false});
  Stream<LocationFix> watch({int distanceFilterMeters = 1});
}

final class LocationUnavailable implements Exception {
  const LocationUnavailable(this.message);
  final String message;
}

/// No GPS coordinates are attached to a photo or its exported bytes.
final class CapturedPhoto {
  const CapturedPhoto(this.bytes, {this.venue, this.fromLibrary = false});
  final Uint8List bytes;
  final PublishedVenue? venue;
  final bool fromLibrary;
}
