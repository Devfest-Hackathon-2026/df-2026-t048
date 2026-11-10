import 'dart:math' as math;

import 'dart:typed_data';
import 'photo_mask.dart';
export 'photo_mask.dart';

enum RedactionStyle { blur, black }

/// Platform independent coordinates. Origin is the image's top-left.
final class ImageRegion {
  const ImageRegion(
    this.x,
    this.y,
    this.width,
    this.height, {
    this.outline,
    this.detectionLabel,
  });
  final double x, y, width, height;
  final List<MaskPoint>? outline;

  /// Optional label returned by an on-device detector, such as `whiteboard`.
  final String? detectionLabel;

  bool get isValid =>
      [x, y, width, height].every((v) => v.isFinite) &&
      x >= 0 &&
      y >= 0 &&
      width > 0 &&
      height > 0 &&
      x + width <= 1.000001 &&
      y + height <= 1.000001;

  static ImageRegion? fromPixels(
    double left,
    double top,
    double width,
    double height,
    int imageWidth,
    int imageHeight,
  ) {
    if (imageWidth <= 0 ||
        imageHeight <= 0 ||
        ![left, top, width, height].every((v) => v.isFinite) ||
        width <= 0 ||
        height <= 0) {
      return null;
    }
    final x1 = (left / imageWidth).clamp(0.0, 1.0);
    final y1 = (top / imageHeight).clamp(0.0, 1.0);
    final x2 = ((left + width) / imageWidth).clamp(0.0, 1.0);
    final y2 = ((top + height) / imageHeight).clamp(0.0, 1.0);
    final rect = ImageRegion(x1, y1, x2 - x1, y2 - y1);
    return rect.isValid ? rect : null;
  }

  ImageRegion padded(double amount) {
    final left = math.max(0.0, x - amount);
    final top = math.max(0.0, y - amount);
    return ImageRegion(
      left,
      top,
      math.min(1.0, x + width + amount) - left,
      math.min(1.0, y + height + amount) - top,
      outline: outline,
      detectionLabel: detectionLabel,
    );
  }
}

final class TextSpanRange {
  const TextSpanRange(this.start, this.end);
  final int start, end;
  bool validFor(String value) =>
      start >= 0 &&
      end > start &&
      end <= value.length &&
      _boundary(value, start) &&
      _boundary(value, end);
  static bool _boundary(String text, int at) =>
      at == 0 ||
      at == text.length ||
      !(text.codeUnitAt(at - 1) >= 0xD800 &&
          text.codeUnitAt(at - 1) <= 0xDBFF &&
          text.codeUnitAt(at) >= 0xDC00 &&
          text.codeUnitAt(at) <= 0xDFFF);
}

final class PhotoInput {
  const PhotoInput({
    required this.bytes,
    required this.width,
    required this.height,
  });
  final Uint8List bytes;
  final int width, height;
}

final class DraftInput {
  const DraftInput({required this.caption, this.photo});
  final String caption;
  final PhotoInput? photo;
}

final class TextBlock {
  const TextBlock({
    required this.id,
    required this.text,
    required this.region,
    this.readings = const [],
  });
  final String id, text;
  final ImageRegion region;
  final List<OcrReading> readings;
  Iterable<String> get texts =>
      readings.isEmpty ? [text] : readings.map((r) => r.text);
}

/// A measured OCR result, never text inferred by the language model.
final class OcrReading {
  const OcrReading({
    required this.text,
    required this.region,
    this.pass = 'original',
    this.tileId,
  });
  final String text, pass;
  final ImageRegion region;
  final int? tileId;
}

final class Observations {
  const Observations({
    this.blocks = const [],
    this.faces = const [],
    this.devices = const [],
    this.notes = const [],
  });
  final List<TextBlock> blocks;
  final List<ImageRegion> faces;
  final List<ImageRegion> devices;
  final List<String> notes;
}

enum FindingKind {
  contact('連絡先'),
  imageText('写り込んだ文字'),
  face('人物'),
  announcement('告知のタイミング'),
  privateWord('登録ワード'),
  context('内容の確認'),
  screenDevice('パソコン・スマホ');

  const FindingKind(this.label);
  final String label;
}

enum FindingSource { rule, mlKit, gemma, manual, deviceModel }

enum ReviewDecision { pending, keep, hide }

sealed class FindingTarget {
  const FindingTarget();
}

final class PhotoTarget extends FindingTarget {
  const PhotoTarget(this.region);
  final ImageRegion region;
}

final class CaptionTarget extends FindingTarget {
  const CaptionTarget(this.range);
  final TextSpanRange range;
}

final class WholePhotoTarget extends FindingTarget {
  const WholePhotoTarget();
}

final class Finding {
  const Finding({
    required this.id,
    required this.kind,
    required this.question,
    required this.target,
    required this.source,
    this.excerpt = '',
    this.ruleEvidence,
    this.targetKey,
    this.detectedLabel,
    this.related = const [],
  });
  final String id, question, excerpt;
  final String? ruleEvidence;
  final String? detectedLabel;

  /// Name shown for an on-device detector result; other findings use the kind.
  String get displayLabel => switch (detectedLabel) {
    'whiteboard' => 'ホワイトボード',
    'wine_glass' => 'お酒（ワイングラス）',
    'book' => '本・資料',
    'picture_frame' => '額縁',
    'poster' => 'ポスター',
    _ => kind.label,
  };

  /// Shared only for an explicitly grounded OCR group, never fuzzy AI text.
  final String? targetKey;
  final List<Finding> related;
  Iterable<Finding> get evidence sync* {
    yield this;
    for (final f in related) {
      yield* f.evidence;
    }
  }

  Set<FindingSource> get sources => evidence.map((f) => f.source).toSet();
  final FindingKind kind;
  final FindingTarget target;
  final FindingSource source;
}

final class ContextResult {
  const ContextResult({
    this.findings = const [],
    required this.status,
    this.venueReviewCompleted = false,
  });
  final List<Finding> findings;
  final String status;

  /// The local model ran with the facility source and returned valid JSON.
  /// This does not assert compliance, completeness, or permission to publish.
  final bool venueReviewCompleted;
}

final class CheckReport {
  const CheckReport({
    required this.findings,
    required this.notes,
    required this.aiStatus,
    required this.elapsed,
    required this.completedAt,
  });
  final List<Finding> findings;
  final List<String> notes;
  final String aiStatus;
  final Duration elapsed;
  final DateTime completedAt;
}

final class ExportArtifact {
  const ExportArtifact({required this.caption, this.imageBytes});
  final String caption;
  final Uint8List? imageBytes;
}
