import 'dart:convert';
import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final image = img.Image(width: 1024, height: 1024, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(37, 99, 235));
  img.fillRect(
    image,
    x1: 225,
    y1: 150,
    x2: 800,
    y2: 870,
    radius: 80,
    color: img.ColorRgb8(255, 255, 255),
  );
  for (final y in [310, 420, 530]) {
    img.fillRect(
      image,
      x1: 315,
      y1: y,
      x2: 665,
      y2: y + 28,
      radius: 14,
      color: img.ColorRgb8(185, 209, 255),
    );
  }
  img.fillCircle(
    image,
    x: 720,
    y: 750,
    radius: 185,
    color: img.ColorRgb8(39, 169, 120),
  );
  img.drawLine(
    image,
    x1: 620,
    y1: 742,
    x2: 697,
    y2: 820,
    thickness: 42,
    color: img.ColorRgb8(255, 255, 255),
  );
  img.drawLine(
    image,
    x1: 697,
    y1: 820,
    x2: 832,
    y2: 665,
    thickness: 42,
    color: img.ColorRgb8(255, 255, 255),
  );
  final directory = Directory('ios/Runner/Assets.xcassets/AppIcon.appiconset');
  final manifest =
      jsonDecode(File('${directory.path}/Contents.json').readAsStringSync())
          as Map;
  for (final icon in manifest['images'] as List) {
    if (icon['filename'] == null) {
      continue;
    }
    final edge =
        (double.parse((icon['size'] as String).split('x').first) *
                double.parse((icon['scale'] as String).replaceAll('x', '')))
            .round();
    File('${directory.path}/${icon['filename']}').writeAsBytesSync(
      img.encodePng(
        img.copyResize(
          image,
          width: edge,
          height: edge,
          interpolation: img.Interpolation.average,
        ),
      ),
    );
  }
}
