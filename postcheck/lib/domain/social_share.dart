import 'dart:typed_data';
import 'models.dart';

enum ShareDestination {
  x,
  line,
  lineOfficial,
  instagramStory,
  instagramPost,
  threads,
  other,
}

enum StoryLayout { card, overlay, photoOnly }

enum ShareHandoff {
  composer,
  sheet,
  captionCopiedSheet,
  storySheet,
  instagramStory,
  officialLineText,
}

final class StoryCaptionTooLong implements Exception {}

final class InvalidLineAccount implements Exception {}

/// Handoff only: an opened composer or share sheet is never proof of posting.
abstract interface class SocialExportPort {
  Future<ShareHandoff> shareTo(
    ExportArtifact artifact,
    ShareDestination destination, {
    StoryLayout storyLayout = StoryLayout.card,
    String? officialLineId,
    double? anchorX,
    double? anchorY,
  });
  Future<Uint8List> previewStory(ExportArtifact artifact, StoryLayout layout);
}
