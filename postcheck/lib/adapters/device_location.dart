import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import '../domain/location.dart';

final class DeviceLocation implements LocationPort {
  const DeviceLocation();

  LocationSettings _settings({int distance = 1, bool once = false}) {
    final limit = once ? const Duration(seconds: 10) : null;
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distance,
        timeLimit: limit,
        allowBackgroundLocationUpdates: false,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: false,
      );
    }
    return LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: distance,
      timeLimit: limit,
    );
  }

  @override
  Future<bool> permitted() async {
    final p = await Geolocator.checkPermission();
    return p == LocationPermission.whileInUse || p == LocationPermission.always;
  }

  @override
  Future<LocationFix> locate({bool requestPermission = false}) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationUnavailable('位置情報が無効です。施設は一覧から変更できます。');
    }
    if (!await permitted()) {
      if (requestPermission) await Geolocator.requestPermission();
      if (!await permitted()) {
        throw const LocationUnavailable('位置情報は未許可です。基本チェックはそのまま使えます。');
      }
    }
    final p = await Geolocator.getCurrentPosition(
      locationSettings: _settings(once: true),
    );
    return LocationFix(p.latitude, p.longitude, p.accuracy, p.timestamp);
  }

  @override
  Stream<LocationFix> watch({int distanceFilterMeters = 1}) async* {
    if (!await permitted() || !await Geolocator.isLocationServiceEnabled()) {
      throw const LocationUnavailable('位置情報を利用できません。権限・端末の設定を確認してください。');
    }
    yield* Geolocator.getPositionStream(
      locationSettings: _settings(distance: distanceFilterMeters),
    ).map((p) => LocationFix(p.latitude, p.longitude, p.accuracy, p.timestamp));
  }
}
