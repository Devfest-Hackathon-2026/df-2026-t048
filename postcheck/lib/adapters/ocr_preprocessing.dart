import 'dart:math' as math;
import 'package:image/image.dart' as img;
import '../domain/models.dart';

final class OcrVariant {
  const OcrVariant(this.photo, this.source, this.pass, {this.tileId});
  final PhotoInput photo;
  final ImageRegion source;
  final String pass;
  final int? tileId;
  ImageRegion? mapBox(double x, double y, double width, double height) {
    final local = ImageRegion.fromPixels(
      x,
      y,
      width,
      height,
      photo.width,
      photo.height,
    );
    if (local == null) return null;
    final region = ImageRegion(
      source.x + local.x * source.width,
      source.y + local.y * source.height,
      local.width * source.width,
      local.height * source.height,
    );
    return region.isValid ? region : null;
  }
}

/// One variant per isolate call: never keep all full-resolution rasters at once.
/// index 0: gamma 1/1.4, indices 1..4: 2x2 tiles with 15% shared overlap.
OcrVariant prepareOcrVariant((PhotoInput, int) request) {
  final (photo, index) = request;
  if (index < 0 || index > 4) throw ArgumentError.value(index);
  var image = img.decodeImage(photo.bytes);
  if (image == null ||
      image.width != photo.width ||
      image.height != photo.height) {
    throw const FormatException('Invalid OCR raster');
  }
  var source = const ImageRegion(0, 0, 1, 1);
  if (index == 0) {
    image = img.gamma(image, gamma: 1 / 1.4);
  } else {
    final tile = index - 1;
    final x0 = tile % 2 == 0 ? 0 : (image.width * .4625).floor();
    final y0 = tile ~/ 2 == 0 ? 0 : (image.height * .4625).floor();
    final x1 = tile % 2 == 0 ? (image.width * .5375).ceil() : image.width;
    final y1 = tile ~/ 2 == 0 ? (image.height * .5375).ceil() : image.height;
    final w = x1 - x0, h = y1 - y0;
    source = ImageRegion(
      x0 / image.width,
      y0 / image.height,
      w / image.width,
      h / image.height,
    );
    image = img.copyCrop(image, x: x0, y: y0, width: w, height: h);
    final longest = math.max(w, h);
    final scale = math.min(2.0, math.max(1.0, 1600 / longest));
    if (scale > 1) {
      image = img.copyResize(
        image,
        width: (w * scale).round(),
        height: (h * scale).round(),
        interpolation: img.Interpolation.cubic,
      );
    }
  }
  // Fresh encoding without EXIF or original thumbnails, including the gamma path.
  final clean = img.Image(
    width: image.width,
    height: image.height,
    numChannels: 3,
  );
  img.compositeImage(clean, image);
  return OcrVariant(
    PhotoInput(
      bytes: img.encodeJpg(clean, quality: 95),
      width: clean.width,
      height: clean.height,
    ),
    source,
    index == 0 ? 'gamma' : 'tile',
    tileId: index == 0 ? null : index - 1,
  );
}
