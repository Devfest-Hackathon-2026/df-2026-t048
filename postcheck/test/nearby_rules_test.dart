import 'package:flutter_test/flutter_test.dart';
import 'package:postcheck/application/nearby_rules.dart';
import 'package:postcheck/domain/location.dart';
import 'package:postcheck_rules/contracts.dart';

PublishedVenue fixture(
  String id, {
  double lat = 35,
  int version = 1,
  DateTime? until,
  String visibility = 'public',
}) => PublishedVenue(
  id: id,
  version: version,
  updatedAt: DateTime.utc(2026),
  policy: VenuePolicy(
    name: id,
    latitude: lat,
    longitude: 139,
    words: ['試作A'],
    validUntil: until,
    visibility: visibility,
  ),
);
void main() {
  late DateTime time;
  late NearbyRules rules;
  void fix(double lat, {double accuracy = 5}) {
    time = time.add(const Duration(seconds: 15));
    rules.observe(LocationFix(lat, 139, accuracy, time));
  }

  setUp(() {
    time = DateTime.utc(2026, 11, 8);
    rules = NearbyRules(now: () => time);
    rules.replaceCatalog([fixture('a'), fixture('b', lat: 35.002)]);
  });
  test('the first usable fix immediately activates the nearest venue', () {
    fix(35);
    expect(rules.active?.id, 'a');
  });
  test(
    'cached fixes and catalogue refreshes cannot confirm a venue switch',
    () {
      fix(35);
      fix(35.002);
      expect(rules.selected?.id, 'a');
      rules.observe(rules.fix!);
      rules.replaceCatalog([fixture('a'), fixture('b', lat: 35.002)]);
      expect(rules.selected?.id, 'a');
      fix(35.002);
      expect(rules.active?.id, 'b');
    },
  );
  test(
    'a GPS fix received before the catalogue selects as soon as it loads',
    () {
      rules.replaceCatalog([]);
      fix(35);
      expect(rules.active, isNull);
      rules.replaceCatalog([fixture('a')]);
      expect(rules.active?.id, 'a');
    },
  );
  test(
    'nearby venues switch even when their distance difference is under 25m',
    () {
      rules.replaceCatalog([fixture('a'), fixture('b', lat: 35.0005)]);
      fix(35);
      for (var i = 0; i < 4; i++) {
        fix(35.0003);
        fix(35.0002);
      }
      expect(
        rules.active?.id,
        'a',
        reason: 'Alternating closest venues must not flicker',
      );
      fix(35.0003);
      expect(rules.active?.id, 'a');
      fix(35.0003);
      expect(rules.active?.id, 'b');
    },
  );
  test('automatic rules never apply outside 500m; manual selection may', () {
    rules.replaceCatalog([fixture('a')]);
    fix(35.00451); // About 501 m.
    expect(rules.active, isNull);
    fix(35.00449); // About 499 m, including the newly supported range.
    expect(rules.active?.id, 'a');
    fix(35.00451);
    expect(rules.active, isNull);
    expect(
      rules.selected?.id,
      'a',
      reason: 'Retained display is not active application',
    );
    rules.choose(fixture('a'));
    expect(rules.active?.id, 'a');
  });
  test('catalogue refresh cannot release an in-range venue after 30s', () {
    rules.replaceCatalog([fixture('a')]);
    fix(35.0036); // About 400 m.
    time = time.add(const Duration(seconds: 31));
    rules.replaceCatalog([fixture('a'), fixture('b', lat: 35.004)]);
    expect(rules.active?.id, 'a');
    fix(35.0036);
    expect(rules.active?.id, 'a');
    fix(35.0036);
    expect(rules.active?.id, 'b');
  });
  test(
    'OFF survives GPS updates, departure and re-entry; explicit ON restores',
    () {
      fix(35);
      fix(35);
      rules.toggle(false);
      fix(35);
      expect(rules.active, isNull);
      fix(36);
      fix(36);
      fix(36);
      expect(rules.selected, isNull);
      fix(35);
      fix(35);
      expect(rules.selected?.id, 'a');
      expect(rules.active, isNull);
      rules.toggle(true);
      expect(rules.active?.id, 'a');
    },
  );
  test('manual selection wins over proximity until automatic reset', () {
    rules.choose(fixture('b', lat: 35.002));
    fix(35);
    fix(35);
    expect(rules.active?.id, 'b');
    rules.automatic();
    fix(35);
    fix(35);
    expect(rules.active?.id, 'a');
  });
  test('poor accuracy, stale and future fixes never newly activate', () {
    fix(35, accuracy: 200);
    fix(35, accuracy: 200);
    expect(rules.active, isNull);
    rules.observe(
      LocationFix(35, 139, 5, time.subtract(const Duration(minutes: 2))),
    );
    expect(rules.active, isNull);
    rules.observe(
      LocationFix(35, 139, 5, time.add(const Duration(minutes: 2))),
    );
    expect(rules.active, isNull);
    // A malformed future fix must not block recovery with real timestamps.
    fix(35);
    fix(35);
    expect(rules.active, isNotNull);
    time = time.add(const Duration(seconds: 61));
    expect(rules.active, isNull);
  });
  test('hysteresis holds existing venue through boundary jitter', () {
    rules.replaceCatalog([fixture('a')]);
    fix(35);
    fix(35);
    for (var i = 0; i < 6; i++) {
      fix(35.00451);
      fix(35.00449);
    }
    expect(rules.selected?.id, 'a');
    fix(35.005); // About 556 m, beyond the departure buffer.
    expect(rules.active, isNull);
    expect(rules.selected?.id, 'a');
    fix(35.005);
    expect(rules.selected?.id, 'a');
    fix(35.005);
    expect(rules.selected, isNull);
  });
  test('revocation, expiry and organization data never remain active', () {
    rules.choose(fixture('a'));
    rules.replaceCatalog([]);
    expect(rules.active, isNull);
    rules.replaceCatalog([
      fixture('a', until: time),
      fixture('private', visibility: 'organization'),
    ]);
    expect(rules.venues, isEmpty);
  });
  test('new public version preserves explicit OFF', () {
    fix(35);
    fix(35);
    rules.toggle(false);
    rules.replaceCatalog([fixture('a', version: 2)]);
    expect(rules.selected?.version, 2);
    expect(rules.active, isNull);
  });
}
