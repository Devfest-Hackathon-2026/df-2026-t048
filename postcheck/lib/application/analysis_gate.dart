/// Shared by on-device adapters. A timeout stops waiting, not native execution.
final class AnalysisGate {
  static final shared = AnalysisGate();
  bool _busy = false;
  bool get busy => _busy;
  bool acquire() {
    if (_busy) return false;
    _busy = true;
    return true;
  }

  void release() => _busy = false;
}
