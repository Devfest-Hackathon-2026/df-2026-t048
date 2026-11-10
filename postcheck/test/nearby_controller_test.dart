import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:postcheck/domain/location.dart';
import 'package:postcheck/presentation/nearby_controller.dart';
import 'package:postcheck_rules/contracts.dart';
import 'nearby_rules_test.dart' show fixture;

class Repository implements VenueRepositoryPort {
  List<PublishedVenue> data = [fixture('a')];
  bool fail = false;
  @override
  Future<List<PublishedVenue>> list() async {
    if (fail) throw StateError('offline');
    return data;
  }
}

class GPS implements LocationPort {
  bool granted = false;
  Completer<LocationFix>? pending;
  int calls = 0;
  @override
  Stream<LocationFix> watch({int distanceFilterMeters = 1}) =>
      const Stream.empty();
  @override
  Future<bool> permitted() async => granted;
  @override
  Future<LocationFix> locate({bool requestPermission = false}) {
    calls++;
    return (pending ??= Completer<LocationFix>()).future;
  }
}

void main() {
  test(
    'denial keeps catalogue usable; explicit location request discarded after background',
    () async {
      final repo = Repository(), gps = GPS();
      final n = NearbyController(repository: repo, location: gps);
      addTearDown(n.dispose);
      await n.start();
      await n.refresh();
      expect(gps.calls, 0);
      final future = n.measure(requestPermission: true);
      n.stop();
      gps.pending!.complete(LocationFix(35, 139, 5, DateTime.now()));
      await future;
      expect(n.active, isNull);
      expect(n.rules.fix, isNull);
    },
  );
  test(
    'failed fetch retains explicit stale indication, successful empty list revokes',
    () async {
      final repo = Repository();
      final n = NearbyController(repository: repo, location: GPS());
      addTearDown(n.dispose);
      await n.refresh();
      n.choose(repo.data.first);
      expect(n.active, isNotNull);
      repo.fail = true;
      await n.refresh();
      expect(n.catalogStale, true);
      expect(n.active, isNotNull);
      repo.fail = false;
      repo.data = [];
      await n.refresh();
      expect(n.active, isNull);
      expect(n.catalogStale, false);
    },
  );
  test(
    'simulation is opt-in and does not reposition fixture coordinates',
    () async {
      final repo = Repository();
      final n = NearbyController(repository: repo, location: GPS(), demo: true);
      addTearDown(n.dispose);
      await n.refresh();
      expect(n.active, isNull);
      await n.simulate();
      expect(n.active?.id, 'a');
      n.toggle(false);
      await n.simulate(outside: true);
      await n.simulate();
      expect(n.active, isNull);
      expect(repo.data.first.policy.latitude, 35);
    },
  );
}
