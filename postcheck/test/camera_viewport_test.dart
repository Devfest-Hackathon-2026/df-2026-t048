import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postcheck/presentation/camera_viewport.dart';

void main() {
  for (final viewport in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets('cover fills $viewport and keeps detection boxes aligned', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(viewport);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const imageKey = ValueKey('image');
      const boxKey = ValueKey('box');
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: CameraViewport(
            aspectRatio: 3 / 4,
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(key: imageKey, color: Color(0xFF333333)),
                  Positioned(
                    left: constraints.maxWidth * .4,
                    top: constraints.maxHeight * .4,
                    width: constraints.maxWidth * .2,
                    height: constraints.maxHeight * .2,
                    child: const ColoredBox(
                      key: boxKey,
                      color: Color(0xFFFFCA70),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final image = tester.getRect(find.byKey(imageKey));
      final box = tester.getRect(find.byKey(boxKey));
      expect(image.width / image.height, closeTo(3 / 4, .0001));
      expect(image.left, lessThanOrEqualTo(0));
      expect(image.top, lessThanOrEqualTo(0));
      expect(image.right, greaterThanOrEqualTo(viewport.width));
      expect(image.bottom, greaterThanOrEqualTo(viewport.height));
      expect(image.center, viewport.center(Offset.zero));
      expect(box.center.dx, closeTo(image.center.dx, .0001));
      expect(box.center.dy, closeTo(image.center.dy, .0001));
      expect(box.width, closeTo(image.width * .2, .0001));
      expect(box.height, closeTo(image.height * .2, .0001));
      expect(tester.takeException(), isNull);
    });
  }
}
