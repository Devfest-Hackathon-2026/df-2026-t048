import 'dart:math' as math;
import '../domain/models.dart';

/// Conservative same-line grouping. No speculative concatenation of partial text.
List<TextBlock> groupOcrReadings(Iterable<OcrReading> input) {
  final groups = <List<OcrReading>>[];
  for (final reading in input) {
    if (!reading.region.isValid || reading.text.trim().isEmpty) continue;
    final matches = groups
        .where(
          (group) =>
              group.any((r) => _sameLine(r, reading)) &&
              group.every(
                (r) =>
                    _rowCompatible(r.region, reading.region) &&
                    _intersection(r.region, reading.region) > 0,
              ),
        )
        .toList();
    if (matches.length == 1) {
      final group = matches.single;
      if (!group.any(
        (r) => r.text == reading.text && _iou(r.region, reading.region) > .98,
      )) {
        group.add(reading);
      }
    } else {
      groups.add([reading]);
    }
  }
  return [
    for (final (i, group) in groups.indexed)
      TextBlock(
        id: 'b$i',
        text: _representative(group).text,
        region: _union(group.map((r) => r.region)),
        readings: List.unmodifiable(group),
      ),
  ];
}

OcrReading _representative(List<OcrReading> readings) {
  // Prefer the complete line; preserve source spelling and all alternative readings.
  return readings.reduce((a, b) => b.text.length > a.text.length ? b : a);
}

bool _sameLine(OcrReading a, OcrReading b) {
  final x = a.region, y = b.region;
  if (!_rowCompatible(x, y)) return false;
  final overlap = _intersection(x, y);
  if (overlap <= 0) return false;
  final sameText = a.text.trim().toLowerCase() == b.text.trim().toLowerCase();
  if (_iou(x, y) >= (sameText ? .65 : .8)) return true;
  final contained =
      overlap / math.min(x.width * x.height, y.width * y.height) >= .9;
  final t = a.text.trim().toLowerCase(), u = b.text.trim().toLowerCase();
  return contained && (t.contains(u) || u.contains(t));
}

bool _rowCompatible(ImageRegion x, ImageRegion y) {
  final minHeight = math.min(x.height, y.height);
  if (math.max(x.height, y.height) / minHeight > 1.6) return false;
  final vertical =
      math.min(x.y + x.height, y.y + y.height) - math.max(x.y, y.y);
  return vertical / minHeight >= .75;
}

double _intersection(ImageRegion a, ImageRegion b) =>
    math.max(0.0, math.min(a.x + a.width, b.x + b.width) - math.max(a.x, b.x)) *
    math.max(
      0.0,
      math.min(a.y + a.height, b.y + b.height) - math.max(a.y, b.y),
    );
double _iou(ImageRegion a, ImageRegion b) {
  final i = _intersection(a, b);
  return i / (a.width * a.height + b.width * b.height - i);
}

ImageRegion _union(Iterable<ImageRegion> regions) {
  final left = regions.map((r) => r.x).reduce(math.min);
  final top = regions.map((r) => r.y).reduce(math.min);
  return ImageRegion(
    left,
    top,
    regions.map((r) => r.x + r.width).reduce(math.max) - left,
    regions.map((r) => r.y + r.height).reduce(math.max) - top,
  );
}

/// Findings remain the review item, with all reasons attached to one decision.
List<Finding> mergeReviewFindings(Iterable<Finding> input) {
  final output = <Finding>[];
  for (final f in input) {
    if (f.targetKey == null &&
        output.any(
          (old) =>
              old.kind == f.kind &&
              old.question == f.question &&
              old.excerpt == f.excerpt &&
              _sameTarget(old.target, f.target),
        )) {
      continue;
    }
    final index = f.targetKey == null
        ? -1
        : output.indexWhere((old) => old.targetKey == f.targetKey);
    if (index < 0) {
      output.add(f);
      continue;
    }
    final old = output[index];
    if (old.evidence.any(
      (e) =>
          e.kind == f.kind &&
          e.question == f.question &&
          e.excerpt == f.excerpt &&
          e.source == f.source &&
          e.ruleEvidence == f.ruleEvidence,
    )) {
      continue;
    }
    output[index] = Finding(
      id: old.id,
      kind: old.kind,
      question: old.question,
      target: old.target,
      source: old.source,
      excerpt: old.excerpt,
      ruleEvidence: old.ruleEvidence,
      targetKey: old.targetKey,
      related: List.unmodifiable([...old.related, f]),
    );
  }
  return List.unmodifiable(output);
}

bool _sameTarget(FindingTarget a, FindingTarget b) => switch ((a, b)) {
  (WholePhotoTarget(), WholePhotoTarget()) => true,
  (CaptionTarget(range: final x), CaptionTarget(range: final y)) =>
    x.start == y.start && x.end == y.end,
  (PhotoTarget(region: final x), PhotoTarget(region: final y)) =>
    x.x == y.x && x.y == y.y && x.width == y.width && x.height == y.height,
  _ => false,
};
