import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:postcheck_rules/contracts.dart';
import '../domain/location.dart';
import '../application/nearby_rules.dart';

final class NearbyController extends ChangeNotifier {
  NearbyController({
    required this.repository,
    required this.location,
    this.demo = false,
    NearbyRules? rules,
  }) : rules = rules ?? NearbyRules();
  final VenueRepositoryPort repository;
  final LocationPort location;
  final bool demo;
  final NearbyRules rules;
  bool loading = false,
      permitted = false,
      foreground = false,
      simulated = false;
  bool catalogLoaded = false,
      catalogStale = false,
      _disposed = false,
      _locating = false;
  String locationMessage = '現在地を使うと、近くの施設ルールを自動で確認します。';
  String catalogMessage = '';
  DateTime? fetchedAt;
  Timer? _timer;
  StreamSubscription<LocationFix>? _positionSubscription;
  int _watchEpoch = 0;
  LocationFix? _demoFix;
  int _request = 0, _locationEpoch = 0, catalogRevision = 0;
  PublishedVenue? get active => rules.active;
  PublishedVenue? get selected => rules.selected;
  LocationFix? get currentLocation =>
      rules.fix?.displayableAt(rules.now()) == true ? rules.fix : null;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start() async {
    if (_disposed || foreground) return;
    foreground = true;
    final epoch = ++_locationEpoch;
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!simulated) {
        _ensureWatch();
        // A stationary device may produce no movement events. Refresh its fix
        // without counting the same cached timestamp as a second observation.
        if (currentLocation == null ||
            rules.now().difference(currentLocation!.at) >=
                const Duration(seconds: 15)) {
          unawaited(measure());
        }
      } else if (_demoFix != null) {
        rules.observe(
          LocationFix(_demoFix!.latitude, _demoFix!.longitude, 5, rules.now()),
        );
      }
      if (fetchedAt == null ||
          DateTime.now().difference(fetchedAt!) >= const Duration(minutes: 1)) {
        unawaited(refresh());
      }
      _emit();
    });
    unawaited(refresh());
    try {
      permitted = await location.permitted();
    } catch (_) {
      permitted = false;
    }
    if (_disposed || !foreground || epoch != _locationEpoch) return;
    if (simulated && _demoFix != null) {
      rules.observe(
        LocationFix(_demoFix!.latitude, _demoFix!.longitude, 5, rules.now()),
      );
    } else if (permitted) {
      _ensureWatch();
      await measure();
    }
    _emit();
  }

  void stop() {
    foreground = false;
    _locationEpoch++;
    _timer?.cancel();
    _cancelWatch();
    rules.invalidateFix();
    _emit();
  }

  Future<void> refresh() async {
    if (_disposed || loading) return;
    final request = ++_request;
    loading = true;
    _emit();
    try {
      final venues = await repository.list();
      if (_disposed || request != _request) return;
      rules.replaceCatalog(venues);
      catalogLoaded = true;
      catalogStale = false;
      catalogRevision++;
      fetchedAt = DateTime.now();
      catalogMessage = '';
    } catch (_) {
      if (!_disposed && request == _request) {
        catalogStale = true;
        catalogMessage = '施設ルールを取得できません。保持した版は最新未確認です。基本チェックは継続できます。';
      }
    } finally {
      if (!_disposed && request == _request) {
        loading = false;
        _emit();
      }
    }
  }

  Future<void> measure({bool requestPermission = false}) async {
    if (_disposed ||
        !foreground ||
        _locating ||
        simulated ||
        (!permitted && !requestPermission)) {
      return;
    }
    final epoch = _locationEpoch;
    final previousFix = rules.fix;
    _locating = true;
    try {
      final fix = await location.locate(requestPermission: requestPermission);
      if (_disposed || !foreground || epoch != _locationEpoch) return;
      permitted = true;
      _acceptFix(fix);
      _ensureWatch();
    } catch (e) {
      if (!_disposed &&
          epoch == _locationEpoch &&
          identical(previousFix, rules.fix)) {
        rules.invalidateFix();
        locationMessage = e is LocationUnavailable
            ? e.message
            : '現在地を取得できません。基本チェックは利用できます。';
      }
    } finally {
      _locating = false;
      if (!_disposed && epoch == _locationEpoch) _emit();
      // An OS permission sheet may cause pause/resume while this request runs.
      if (!_disposed &&
          foreground &&
          epoch != _locationEpoch &&
          permitted &&
          !simulated &&
          currentLocation == null) {
        unawaited(measure());
      }
    }
  }

  void _acceptFix(LocationFix fix) {
    final old = rules.fix;
    if (old != null &&
        old.displayableAt(rules.now()) &&
        !fix.at.isAfter(old.at)) {
      return;
    }
    rules.observe(fix);
    locationMessage = rules.fresh
        ? '現在地を更新中・約1mの移動を目安に反映します。'
        : '位置の精度・鮮度が足りないため、施設の自動適用を保留しています。';
    _emit();
  }

  void _cancelWatch() {
    _watchEpoch++;
    final subscription = _positionSubscription;
    _positionSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
  }

  void _ensureWatch() {
    if (_disposed ||
        !foreground ||
        simulated ||
        !permitted ||
        _positionSubscription != null) {
      return;
    }
    final epoch = ++_watchEpoch;
    void failed(Object error) {
      if (_disposed || epoch != _watchEpoch) return;
      _cancelWatch();
      rules.invalidateFix();
      locationMessage = error is LocationUnavailable
          ? error.message
          : '現在地の更新が止まりました。再確認を押してください。';
      _emit();
    }

    try {
      _positionSubscription = location
          .watch(distanceFilterMeters: 1)
          .listen(
            (fix) {
              if (!_disposed &&
                  foreground &&
                  !simulated &&
                  epoch == _watchEpoch) {
                _acceptFix(fix);
              }
            },
            onError: failed,
            onDone: () {
              if (!_disposed && epoch == _watchEpoch) {
                _positionSubscription = null;
                _watchEpoch++;
              }
            },
            cancelOnError: true,
          );
    } catch (error) {
      failed(error);
    }
  }

  Future<void> useCurrentLocation() async {
    final wasSimulated = simulated;
    simulated = false;
    _demoFix = null;
    _locationEpoch++;
    _cancelWatch();
    rules.invalidateFix();
    if (wasSimulated && !rules.manual) rules.selected = null;
    locationMessage = '現在地を取得しています…';
    _emit();
    await measure(requestPermission: true);
    _ensureWatch();
  }

  void choose(PublishedVenue v) {
    rules.choose(v);
    _emit();
  }

  void toggle(bool on) {
    rules.toggle(on);
    _emit();
  }

  void automatic() {
    simulated = false;
    rules.automatic();
    _locationEpoch++;
    _cancelWatch();
    locationMessage = '近くの施設を確認します。';
    _emit();
    _ensureWatch();
    unawaited(measure());
  }

  /// Explicit demo action; never moves fixtures to the user's real location.
  Future<void> simulate({bool outside = false}) async {
    if (!demo) return;
    _locationEpoch++;
    _cancelWatch();
    simulated = true;
    rules.manual = false;
    rules.invalidateFix();
    if (!catalogLoaded) await refresh();
    if (_disposed) return;
    final target = rules.venues.firstOrNull;
    if (target == null) return;
    final now = rules.now();
    final lat = target.policy.latitude + (outside ? .01 : 0);
    final lng = target.policy.longitude;
    _demoFix = LocationFix(lat, lng, 5, now);
    if (outside) {
      // Explicit demo shortcut; real GPS departure uses the 30-second grace.
      rules.observe(LocationFix(lat, lng, 5, now));
      rules.selected = null;
    } else {
      rules.observe(
        LocationFix(lat, lng, 5, now.subtract(const Duration(seconds: 1))),
      );
      rules.observe(LocationFix(lat, lng, 5, now));
    }
    locationMessage = outside ? '架空の位置：施設の外' : '架空の位置：展示館の近く';
    _emit();
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    _locationEpoch++;
    _timer?.cancel();
    _cancelWatch();
    super.dispose();
  }
}
