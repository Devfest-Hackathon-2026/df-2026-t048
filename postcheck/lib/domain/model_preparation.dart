enum ModelPreparationPhase {
  waiting,
  downloading,
  verifying,
  ready,
  paused,
  failed,
  unavailable,
}

final class ModelPreparation {
  const ModelPreparation({
    required this.phase,
    this.receivedBytes = 0,
    this.totalBytes = 2588147712,
  });
  final ModelPreparationPhase phase;
  final int receivedBytes, totalBytes;
  bool get isActive => const {
    ModelPreparationPhase.waiting,
    ModelPreparationPhase.downloading,
    ModelPreparationPhase.verifying,
  }.contains(phase);
  double? get progress =>
      totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : null;
}
