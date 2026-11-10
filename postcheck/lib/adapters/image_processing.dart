import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'dart:math' as math;
import '../domain/models.dart';
import '../domain/ports.dart';

final class RasterImageAdapter implements ImageProcessingPort {
  const RasterImageAdapter();
  @override
  Future<PhotoInput> prepare(Uint8List bytes) => compute(prepareRaster, bytes);

  @override
  Future<Uint8List> redact(
    PhotoInput photo,
    List<PhotoMask> regions, {
    RedactionStyle style = RedactionStyle.black,
  }) => compute(redactMaskRaster, (photo, regions, style));
}

PhotoInput prepareRaster(Uint8List bytes) {
  if (bytes.length > 60 * 1024 * 1024) {
    throw const FormatException('画像が大きすぎます。60MB以下の写真を選んでください。');
  }
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('画像を読み込めませんでした。JPEGまたはPNGを選んでください。');
  }
  var oriented = img.bakeOrientation(decoded);
  final longest = oriented.width > oriented.height
      ? oriented.width
      : oriented.height;
  if (longest > 2400) {
    oriented = img.copyResize(
      oriented,
      width: (oriented.width * 2400 / longest).round(),
      height: (oriented.height * 2400 / longest).round(),
      interpolation: img.Interpolation.average,
    );
  }
  // A fresh raster prevents copying EXIF/GPS, embedded thumbnails and other metadata.
  final clean = img.Image(
    width: oriented.width,
    height: oriented.height,
    numChannels: 3,
  );
  img.fill(clean, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(clean, oriented);
  return PhotoInput(
    bytes: Uint8List.fromList(img.encodeJpg(clean, quality: 95)),
    width: clean.width,
    height: clean.height,
  );
}

Uint8List redactRaster((PhotoInput, List<ImageRegion>) input) =>
    redactRasterWithStyle((input.$1, input.$2, RedactionStyle.black));

Uint8List redactRasterWithStyle(
  (PhotoInput, List<ImageRegion>, RedactionStyle) input,
) => redactMaskRaster((
  input.$1,
  input.$2.map(PhotoMask.region).toList(),
  input.$3,
));

/// Ordered coverage operations. Erasing restores original pixels, not white paint.
Uint8List redactMaskRaster(
  (PhotoInput, List<PhotoMask>, RedactionStyle) input,
) {
  final (photo, masks, style) = input;
  if (masks.any((m) => !m.isValid)) {
    throw const FormatException('マスクの範囲が不正です。');
  }
  final source = img.decodeImage(photo.bytes);
  if (source == null) throw const FormatException('画像を読み込めませんでした。');
  final w = source.width, h = source.height;
  final coverage = Uint8List(w * h);
  for (final mask in masks) {
    for (final op in mask.operations) {
      final points = op.points;
      if (op.kind == MaskOperationKind.polygon) {
        final top = (points.map((p) => p.y).reduce(math.min) * h).floor().clamp(
          0,
          h - 1,
        );
        final bottom = (points.map((p) => p.y).reduce(math.max) * h)
            .ceil()
            .clamp(0, h - 1);
        for (var y = top; y <= bottom; y++) {
          final crossings = <double>[];
          for (var i = 0; i < points.length; i++) {
            final a = points[i], b = points[(i + 1) % points.length];
            final ay = a.y * h, by = b.y * h;
            if ((ay <= y && by > y) || (by <= y && ay > y)) {
              crossings.add(a.x * w + (y - ay) * (b.x - a.x) * w / (by - ay));
            }
          }
          crossings.sort();
          for (var i = 0; i + 1 < crossings.length; i += 2) {
            final left = crossings[i].floor().clamp(0, w - 1);
            final right = crossings[i + 1].ceil().clamp(0, w - 1);
            coverage.fillRange(y * w + left, y * w + right + 1, 255);
          }
        }
      } else {
        final radius = op.diameter * math.min(w, h) / 2;
        final value = op.kind == MaskOperationKind.erase ? 0 : 255;
        void stamp(double cx, double cy) {
          final top = (cy - radius).floor().clamp(0, h - 1);
          final bottom = (cy + radius).ceil().clamp(0, h - 1);
          for (var y = top; y <= bottom; y++) {
            final squared = radius * radius - (y - cy) * (y - cy);
            if (squared < 0) continue;
            final extent = math.sqrt(squared);
            final left = (cx - extent).ceil().clamp(0, w - 1);
            final right = (cx + extent).floor().clamp(0, w - 1);
            if (left <= right) {
              coverage.fillRange(y * w + left, y * w + right + 1, value);
            }
          }
        }

        stamp(points.first.x * w, points.first.y * h);
        for (var i = 1; i < points.length; i++) {
          final a = points[i - 1], b = points[i];
          final dx = (b.x - a.x) * w, dy = (b.y - a.y) * h;
          final steps =
              (math.sqrt(dx * dx + dy * dy) / math.max(.5, radius / 3))
                  .ceil()
                  .clamp(1, 20000);
          for (var j = 1; j <= steps; j++) {
            stamp(a.x * w + dx * j / steps, a.y * h + dy * j / steps);
          }
        }
      }
    }
  }
  img.Image? blurred;
  if (style == RedactionStyle.blur && coverage.any((v) => v != 0)) {
    final small = img.copyResize(
      source,
      // Same normalized blur strength for the reduced preview and full export.
      width: (w * 64 / math.max(w, h)).round().clamp(1, w),
      height: (h * 64 / math.max(w, h)).round().clamp(1, h),
      interpolation: img.Interpolation.average,
    );
    blurred = img.copyResize(
      img.gaussianBlur(small, radius: 2),
      width: w,
      height: h,
      interpolation: img.Interpolation.linear,
    );
  }
  // New raster strips metadata and embeds the effect into the exported pixels.
  final clean = img.Image(width: w, height: h, numChannels: 3);
  img.compositeImage(clean, source);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (coverage[y * w + x] == 0) continue;
      if (blurred == null) {
        clean.setPixelRgb(x, y, 0, 0, 0);
      } else {
        final pixel = blurred.getPixel(x, y);
        clean.setPixelRgb(x, y, pixel.r, pixel.g, pixel.b);
      }
    }
  }
  return Uint8List.fromList(img.encodePng(clean));
}
