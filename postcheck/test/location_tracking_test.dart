import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:postcheck/application/map_follow.dart';
import 'package:postcheck/application/nearby_rules.dart';
import 'package:postcheck/domain/location.dart';
import 'package:postcheck/presentation/nearby_controller.dart';
import 'package:postcheck_rules/contracts.dart';
import 'nearby_controller_test.dart' show Repository;
import 'nearby_rules_test.dart' show fixture;

class _DelayedRepository extends Repository {
  final pending = Completer<List<PublishedVenue>>();
  @override
  Future<List<PublishedVenue>> list() => pending.future;
}

class StreamingGPS implements LocationPort {
  bool granted = true;
  int? distance;
  int cancellations = 0;
  LocationFix fix = LocationFix(35, 139, 5, DateTime.utc(2026, 11, 8));
  Completer<LocationFix>? pending;
  final streams = <StreamController<LocationFix>>[];
  @override
  Future<bool> permitted() async => granted;
  @override
  Future<LocationFix> locate({bool requestPermission = false}) async {
    if (!granted) throw const LocationUnavailable('位置情報は未許可です');
    return pending == null ? fix : pending!.future;
  }

  @override
  Stream<LocationFix> watch({int distanceFilterMeters = 1}) {
    distance = distanceFilterMeters;
    final s = StreamController<LocationFix>(onCancel: () => cancellations++);
    streams.add(s);
    return s.stream;
  }

  Future<void> close() async {
    for (final s in streams) {
      await s.close();
    }
  }
}

void main() {
  late StreamingGPS gps;
  late NearbyController n;
  late DateTime time;
  setUp(() {
    gps = StreamingGPS();
    time = gps.fix.at;
    n = NearbyController(
      repository: Repository(),
      location: gps,
      demo: true,
      rules: NearbyRules(now: () => time),
    );
  });
  tearDown(() async {
    n.dispose();
    await gps.close();
  });
  Future<void> emit(double latitude, {double accuracy = 5}) async {
    time = time.add(const Duration(seconds: 5));
    gps.fix = LocationFix(latitude, 139, accuracy, time);
    gps.streams.last.add(gps.fix);
    await Future<void>.delayed(Duration.zero);
  }

  test(
    'catalogue arriving after GPS activates without another location event',
    () async {
      final repository = _DelayedRepository();
      final delayed = NearbyController(
        repository: repository,
        location: gps,
        rules: NearbyRules(now: () => time),
      );
      addTearDown(delayed.dispose);
      await delayed.start();
      expect(delayed.currentLocation, isNotNull);
      expect(delayed.active, isNull);
      repository.pending.complete([fixture('a')]);
      await Future<void>.delayed(Duration.zero);
      expect(delayed.active?.id, 'a');
      expect(delayed.catalogLoaded, isTrue);
    },
  );

  test(
    'stream switches to nearest; manual choice persists until automatic reset',
    () async {
      await n.start();
      n.rules.replaceCatalog([fixture('a'), fixture('b', lat: 35.0005)]);
      await emit(35.0003);
      await emit(35.0003);
      expect(n.active?.id, 'b');
      n.choose(fixture('a'));
      await emit(35.0005);
      await emit(35.0005);
      expect(n.active?.id, 'a');
      n.automatic();
      await Future<void>.delayed(Duration.zero);
      expect(n.rules.manual, isFalse);
      expect(n.active?.id, 'b');
    },
  );

  test(
    '1m stream updates position and rules; user OFF survives movement',
    () async {
      await n.start();
      expect(gps.distance, 1);
      await emit(35.00001);
      expect(n.currentLocation?.latitude, 35.00001);
      expect(n.active?.id, 'a');
      n.toggle(false);
      await emit(35.0001);
      expect(n.currentLocation?.latitude, 35.0001);
      expect(n.active, isNull);
    },
  );

  test(
    'background cancels stream, rejects queued data; resume creates one listener',
    () async {
      await n.start();
      final old = gps.streams.last;
      n.stop();
      old.add(LocationFix(36, 139, 5, time));
      await Future<void>.delayed(Duration.zero);
      expect(gps.cancellations, 1);
      expect(n.currentLocation, isNull);
      await n.start();
      await n.start();
      expect(gps.streams.length, 2);
      await emit(35.0001);
      expect(n.currentLocation?.latitude, 35.0001);
    },
  );

  test(
    'late single-shot response cannot move marker back after stream update',
    () async {
      await n.start();
      gps.pending = Completer<LocationFix>();
      final old = gps.fix;
      final request = n.measure();
      await emit(35.0001);
      gps.pending!.complete(old);
      await request;
      expect(n.currentLocation?.latitude, 35.0001);
    },
  );

  test(
    'simulation suspends real tracking; current location restores it without clearing OFF',
    () async {
      await n.start();
      await emit(35.00001);
      n.toggle(false);
      await n.simulate();
      expect(gps.cancellations, 1);
      expect(n.simulated, true);
      await n.useCurrentLocation();
      expect(n.simulated, false);
      expect(gps.streams.length, 2);
      await emit(35.0001);
      expect(n.active, isNull);
      expect(n.currentLocation?.latitude, 35.0001);
    },
  );

  test(
    'coarse location is displayable but cannot auto-activate; expired marker disappears',
    () async {
      await n.start();
      await emit(35, accuracy: 300);
      expect(n.currentLocation?.accuracy, 300);
      expect(n.active, isNull);
      time = time.add(const Duration(seconds: 61));
      expect(n.currentLocation, isNull);
    },
  );

  test(
    'permission denied starts no stream and retains base-only use',
    () async {
      gps.granted = false;
      await n.start();
      await n.useCurrentLocation();
      expect(gps.streams, isEmpty);
      expect(n.currentLocation, isNull);
      expect(n.locationMessage, contains('未許可'));
    },
  );

  test(
    'map follows 1m movement; panning pauses and explicit recenter resumes',
    () {
      final follow = MapFollow();
      LocationFix point(double lat) => LocationFix(lat, 139, 5, time);
      expect(follow.update(point(35), time), isNotNull);
      expect(follow.update(point(35.000004), time), isNull);
      expect(follow.update(point(35.00001), time), isNotNull);
      follow.pause();
      expect(follow.update(point(35.0001), time), isNull);
      follow.resume();
      expect(follow.update(point(35.0001), time)?.latitude, 35.0001);
    },
  );

  test('map never follows malformed or stale positions', () {
    final follow = MapFollow();
    expect(follow.update(LocationFix(95, 139, 5, time), time), isNull);
    expect(
      follow.update(
        LocationFix(35, 139, 5, time),
        time.add(const Duration(minutes: 2)),
      ),
      isNull,
    );
    expect(follow.update(LocationFix(35, 139, double.nan, time), time), isNull);
  });
}
