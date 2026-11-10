import 'dart:math' as math;
import 'models.dart';

/// Normalized original-image coordinates; no UI/SDK types in mask data.
final class MaskPoint {
  const MaskPoint(this.x, this.y);
  final double x, y;
  bool get isValid =>
      x.isFinite && y.isFinite && x >= 0 && x <= 1 && y >= 0 && y <= 1;
}

enum MaskOperationKind { polygon, brush, erase }

final class MaskOperation {
  MaskOperation(this.kind, List<MaskPoint> points, {this.diameter = .04})
    : points = List.unmodifiable(points);
  final MaskOperationKind kind;
  final List<MaskPoint> points;

  /// Fraction of the shorter image side, so brush strokes stay circular.
  final double diameter;
  bool get isValid =>
      points.every((p) => p.isValid) &&
      (kind == MaskOperationKind.polygon
          ? points.length >= 3 && area > .000001
          : points.isNotEmpty &&
                diameter.isFinite &&
                diameter > 0 &&
                diameter <= 1);
  double get area {
    var sum = 0.0;
    for (var i = 0; i < points.length; i++) {
      final a = points[i], b = points[(i + 1) % points.length];
      sum += a.x * b.y - b.x * a.y;
    }
    return sum.abs() / 2;
  }
}

final class PhotoMask {
  PhotoMask(List<MaskOperation> operations)
    : operations = List.unmodifiable(operations);
  factory PhotoMask.region(ImageRegion region) {
    final r = region.outline == null ? region.padded(.003) : region;
    return PhotoMask([
      MaskOperation(
        MaskOperationKind.polygon,
        r.outline ??
            [
              MaskPoint(r.x, r.y),
              MaskPoint(r.x + r.width, r.y),
              MaskPoint(r.x + r.width, r.y + r.height),
              MaskPoint(r.x, r.y + r.height),
            ],
      ),
    ]);
  }
  final List<MaskOperation> operations;
  bool get isValid => operations.every((o) => o.isValid);
  bool get isEmpty => operations.isEmpty;

  static MaskOperation regularPolygon(int corners, ImageRegion bounds) {
    if (corners == 4) {
      return PhotoMask.region(bounds).operations.single;
    }
    return MaskOperation(
      MaskOperationKind.polygon,
      List.generate(corners, (i) {
        final angle = -math.pi / 2 + i * 2 * math.pi / corners;
        return MaskPoint(
          bounds.x + bounds.width * (.5 + .5 * math.cos(angle)),
          bounds.y + bounds.height * (.5 + .5 * math.sin(angle)),
        );
      }),
    );
  }
}
