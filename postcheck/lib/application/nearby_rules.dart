import 'dart:math' as math;
import 'package:postcheck_rules/contracts.dart';
import '../domain/location.dart';

/// SDK-independent proximity and user intent. Automatic selection is limited
/// to the user-specified 500 m radius; departure timing is a trial default.
final class NearbyRules {
  NearbyRules({DateTime Function()? now}) : now = now ?? DateTime.now;
  static const automaticRadiusMeters = 500.0;
  // Keep the existing 50 m departure buffer outside the automatic radius.
  static const departureRadiusMeters = automaticRadiusMeters + 50;
  final DateTime Function() now;
  List<PublishedVenue> venues = [];
  LocationFix? fix;
  PublishedVenue? selected;
  bool manual = false;
  final _off = <String>{};
  String? _pending;
  int _hits = 0;
  DateTime? _outsideSince;

  bool get fresh => fix?.usableAt(now()) == true;
  PublishedVenue? get active =>
      selected != null &&
          selected!.policy.validAt(now()) &&
          !_off.contains(selected!.id) &&
          (manual ||
              (fresh && distance(fix!, selected!) <= automaticRadiusMeters))
      ? selected
      : null;
  bool get switchedOff => selected != null && _off.contains(selected!.id);

  void replaceCatalog(List<PublishedVenue> values) {
    venues = values
        .where(
          (v) => v.policy.visibility == 'public' && v.policy.validAt(now()),
        )
        .toList();
    if (selected != null) {
      selected = venues.where((v) => v.id == selected!.id).firstOrNull;
    }
    // The initial GPS fix can arrive before the public catalogue. Evaluate
    // it now instead of waiting for a movement event or the next GPS poll.
    _evaluate(newObservation: false);
  }

  void choose(PublishedVenue value) {
    final current = venues
        .where((v) => v.id == value.id && v.version == value.version)
        .firstOrNull;
    if (current == null || !current.policy.validAt(now())) return;
    manual = true;
    selected = current;
    _off.remove(current.id);
    _clearPending();
  }

  void toggle(bool on) {
    if (selected == null) return;
    if (on) {
      _off.remove(selected!.id);
      // Explicit ON confirms the chosen place even when GPS is unavailable.
      manual = true;
    } else {
      _off.add(selected!.id);
    }
  }

  void automatic() {
    manual = false;
    selected = null;
    _off.clear();
    _clearPending();
    fix = null;
  }

  void invalidateFix() {
    fix = null;
    _clearPending();
  }

  void _clearPending() {
    _pending = null;
    _hits = 0;
    _outsideSince = null;
  }

  void observe(LocationFix value) {
    final previous = fix;
    fix = value;
    if (manual) return;
    if (!fresh) {
      _clearPending();
      return;
    }
    // Re-reading a cached fix must not count as two independent observations.
    if (previous != null &&
        previous.usableAt(now()) &&
        !value.at.isAfter(previous.at)) {
      return;
    }
    _evaluate(newObservation: true);
  }

  void _evaluate({required bool newObservation}) {
    if (manual || !fresh) return;
    final value = fix!;
    final eligible = venues.where((v) => v.policy.validAt(now())).toList()
      ..sort((a, b) {
        final c = distance(value, a).compareTo(distance(value, b));
        return c == 0 ? a.id.compareTo(b.id) : c;
      });
    final closest = eligible
        .where((v) => distance(value, v) <= automaticRadiusMeters)
        .firstOrNull;
    if (selected != null &&
        (!selected!.policy.validAt(now()) ||
            distance(value, selected!) > departureRadiusMeters)) {
      _outsideSince ??= now();
      if (now().difference(_outsideSince!) >= const Duration(seconds: 30)) {
        selected = null;
      }
    } else {
      _outsideSince = null;
    }
    if (closest == null) {
      _pending = null;
      _hits = 0;
      return;
    }
    // The first usable location selects immediately. Stability confirmation
    // is needed only when replacing an already selected venue.
    if (selected == null) {
      selected = closest;
      _clearPending();
      return;
    }
    if (selected?.id == closest.id) {
      _pending = null;
      _hits = 0;
      return;
    }
    // Catalogue refreshes must not count as independent GPS confirmations.
    if (!newObservation) {
      if (_pending != closest.id) {
        _pending = null;
        _hits = 0;
      }
      return;
    }
    if (_pending == closest.id) {
      _hits++;
    } else {
      _pending = closest.id;
      _hits = 1;
    }
    if (_hits >= 2) {
      selected = closest;
      _clearPending();
    }
  }

  static double distance(LocationFix f, PublishedVenue v) {
    const r = math.pi / 180;
    final dlat = (v.policy.latitude - f.latitude) * r;
    final dlng = (v.policy.longitude - f.longitude) * r;
    final h =
        math.pow(math.sin(dlat / 2), 2) +
        math.cos(f.latitude * r) *
            math.cos(v.policy.latitude * r) *
            math.pow(math.sin(dlng / 2), 2);
    return 6371000 * 2 * math.asin(math.sqrt(h.clamp(0, 1)));
  }
}
