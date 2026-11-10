/// Pure scheduling state: at most one inference, no frame queue or stale boxes.
final class LiveFrameGate {
  int _generation = 0;
  int? _startedAt;
  int _lastStart = -1000;
  int get generation => _generation;
  int? begin(int now) {
    if (_startedAt != null || now - _lastStart < 750) return null;
    _startedAt = now;
    _lastStart = now;
    return _generation;
  }

  bool finish(int generation, int startedAt, int now) {
    _startedAt = null;
    return generation == _generation && now - startedAt <= 2000;
  }

  void invalidate() {
    _generation++;
  }
}
