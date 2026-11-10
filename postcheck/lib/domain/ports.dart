import 'dart:typed_data';
import 'package:postcheck_rules/contracts.dart';
import 'models.dart';

abstract interface class PerceptionPort {
  Future<Observations> inspect(PhotoInput photo);
}

/// Optional progressive contract; simple/offline implementations can keep inspect.
abstract interface class ProgressivePerceptionPort implements PerceptionPort {
  bool get isRunning;
  Duration get additionalBudget;
  Future<Observations> inspectProgressively(
    PhotoInput photo, {
    required Duration budget,
    required bool Function() shouldStop,
    required void Function(Observations observations, bool basicComplete)
    onPartial,
    void Function(String message)? onProgress,
  });
}

abstract interface class ContextAnalysisPort {
  Future<ContextResult> analyze(
    DraftInput draft,
    Observations observations, {
    PublishedVenue? venue,
  });
}

abstract interface class ImageProcessingPort {
  Future<PhotoInput> prepare(Uint8List bytes);
  Future<Uint8List> redact(
    PhotoInput photo,
    List<PhotoMask> regions, {
    RedactionStyle style = RedactionStyle.black,
  });
}

abstract interface class ExportPort {
  Future<void> share(
    ExportArtifact artifact, {
    double? anchorX,
    double? anchorY,
  });
}

abstract interface class PhotoSavePort {
  Future<void> savePhoto(Uint8List png);
}

abstract interface class FileSavePort {
  /// False means the user dismissed the destination picker.
  Future<bool> saveFile(Uint8List png);
}

final class PhotoPermissionDenied implements Exception {}
