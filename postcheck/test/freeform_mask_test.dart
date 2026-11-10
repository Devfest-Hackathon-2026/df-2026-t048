import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:postcheck/domain/models.dart';
import 'package:postcheck/adapters/image_processing.dart';

PhotoInput fixture({int width = 100, int height = 100}) {
  final image = img.Image(width: width, height: height, numChannels: 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, (x + y).isEven ? 240 : 80, 160, 100);
    }
  }
  return PhotoInput(
    bytes: Uint8List.fromList(img.encodePng(image)),
    width: width,
    height: height,
  );
}

img.Image render(
  PhotoInput photo,
  List<MaskOperation> operations, {
  RedactionStyle style = RedactionStyle.black,
}) => img.decodePng(redactMaskRaster((photo, [PhotoMask(operations)], style)))!;

void main() {
  test(
    'triangle and trapezoid do not mask the surrounding bounding rectangle',
    () {
      final photo = fixture();
      final triangle = MaskOperation(MaskOperationKind.polygon, const [
        MaskPoint(.5, .1),
        MaskPoint(.9, .9),
        MaskPoint(.1, .9),
      ]);
      final result = render(photo, [triangle]);
      expect(result.getPixel(50, 50).r, 0);
      expect(result.getPixel(15, 15).r, 240);
      final trapezoid = MaskOperation(MaskOperationKind.polygon, const [
        MaskPoint(.3, .2),
        MaskPoint(.7, .2),
        MaskPoint(.9, .8),
        MaskPoint(.1, .8),
      ]);
      final output = render(photo, [trapezoid]);
      expect(output.getPixel(50, 30).r, 0);
      expect(output.getPixel(12, 25).r, 80);
      expect(output.getPixel(20, 70).r, 0);
    },
  );
  test('eraser restores original pixels and later brush repaints them', () {
    final photo = fixture();
    final base = PhotoMask.region(
      const ImageRegion(.1, .1, .8, .8),
    ).operations.single;
    final erase = MaskOperation(MaskOperationKind.erase, const [
      MaskPoint(.3, .5),
      MaskPoint(.7, .5),
    ], diameter: .2);
    final output = render(photo, [base, erase]);
    expect(output.getPixel(50, 50).r, 240);
    expect(output.getPixel(50, 30).r, 0);
    final brush = MaskOperation(MaskOperationKind.brush, const [
      MaskPoint(.5, .5),
    ], diameter: .06);
    expect(render(photo, [base, erase, brush]).getPixel(50, 50).r, 0);
  });
  test(
    'brush is circular on non-square photos, interpolates and honors width',
    () {
      final photo = fixture(width: 200, height: 100);
      final dot = MaskOperation(MaskOperationKind.brush, const [
        MaskPoint(.5, .5),
      ], diameter: .2);
      final output = render(photo, [dot]);
      expect(output.getPixel(109, 50).r, 0);
      expect(output.getPixel(100, 59).r, 0);
      expect(output.getPixel(115, 50).r, 80);
      final line = MaskOperation(MaskOperationKind.brush, const [
        MaskPoint(.1, .5),
        MaskPoint(.9, .5),
      ], diameter: .04);
      final painted = render(photo, [line]);
      for (var x = 20; x <= 180; x++) {
        expect(painted.getPixel(x, 50).r, 0);
      }
      expect(painted.getPixel(100, 54).r, 240);
    },
  );
  test(
    'blur and black share the same contour; erased blur restores source',
    () {
      final photo = fixture();
      final polygon = MaskOperation(MaskOperationKind.polygon, const [
        MaskPoint(.5, .1),
        MaskPoint(.9, .9),
        MaskPoint(.1, .9),
      ]);
      final erase = MaskOperation(MaskOperationKind.erase, const [
        MaskPoint(.5, .5),
      ], diameter: .1);
      final result = render(photo, [
        polygon,
        erase,
      ], style: RedactionStyle.blur);
      expect(result.getPixel(50, 50).r, 240);
      expect(result.getPixel(50, 70).r, inInclusiveRange(90, 220));
      expect(result.getPixel(15, 15).r, 240);
      expect(result.exif.isEmpty, isTrue);
    },
  );
  test(
    'invalid masks fail instead of silently exporting unredacted content',
    () {
      expect(
        () => render(fixture(), [
          MaskOperation(MaskOperationKind.polygon, const [
            MaskPoint(-.1, 0),
            MaskPoint(.5, .5),
            MaskPoint(1, 1),
          ]),
        ]),
        throwsFormatException,
      );
      expect(
        () => render(fixture(), [
          MaskOperation(MaskOperationKind.brush, const [
            MaskPoint(.5, .5),
          ], diameter: double.nan),
        ]),
        throwsFormatException,
      );
    },
  );
}
