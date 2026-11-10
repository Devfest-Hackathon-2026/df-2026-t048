import '../domain/location.dart';

/// Map browsing never changes the selected venue or its rule toggle.
final class MapFollow {
  bool following = true;
  LocationFix? _center;
  void pause() => following = false;
  void resume() {
    following = true;
    _center = null;
  }

  LocationFix? update(LocationFix? fix, DateTime now) {
    if (!following || fix == null || !fix.displayableAt(now)) return null;
    if (_center != null &&
        _center!.displayableAt(now) &&
        _center!.distanceTo(fix) < 1) {
      return null;
    }
    _center = fix;
    return fix;
  }
}
