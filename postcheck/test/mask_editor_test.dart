import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postcheck/domain/models.dart';
import 'package:postcheck/domain/ports.dart';
import 'package:postcheck/adapters/image_processing.dart';
import 'package:postcheck/presentation/mask_editor.dart';
import 'freeform_mask_test.dart' show fixture;

class EditorImages implements ImageProcessingPort {
  @override
  Future<PhotoInput> prepare(Uint8List bytes) async => prepareRaster(bytes);
  @override
  Future<Uint8List> redact(
    PhotoInput photo,
    List<PhotoMask> masks, {
    RedactionStyle style = RedactionStyle.black,
  }) async => redactMaskRaster((photo, masks, style));
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('drag one corner independently, undo/redo, commit a trapezoid', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final original = PhotoMask.region(const ImageRegion(.2, .2, .6, .6));
    PhotoMask? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.push<PhotoMask>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MaskEditor(
                      photo: fixture(),
                      images: EditorImages(),
                      style: RedactionStyle.black,
                      initial: original,
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    final rect = tester.getRect(find.byType(Image));
    final start =
        rect.topLeft +
        Offset(
          original.operations.single.points.first.x * rect.width,
          original.operations.single.points.first.y * rect.height,
        );
    await tester.dragFrom(start, const Offset(35, 12));
    await settle(tester);
    await tester.tap(find.byTooltip('元に戻す'));
    await settle(tester);
    await tester.tap(find.byTooltip('やり直す'));
    await settle(tester);
    await tester.tap(find.text('完了'));
    await settle(tester);
    expect(result, isNotNull);
    final points = result!.operations.single.points;
    expect(
      points.first.x,
      greaterThan(original.operations.single.points.first.x + .05),
    );
    expect(points[1].x, original.operations.single.points[1].x);
    expect(points[1].y, original.operations.single.points[1].y);
    expect(original.operations.single.points.first.x, closeTo(.197, .0001));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'brush width, erase, undo and cancel remain a local transaction',
    (tester) async {
      final original = PhotoMask([]);
      PhotoMask? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.push<PhotoMask>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MaskEditor(
                        photo: fixture(width: 200, height: 100),
                        images: EditorImages(),
                        style: RedactionStyle.blur,
                        initial: original,
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settle(tester);
      expect(find.byType(Slider), findsOneWidget);
      await tester.drag(find.byType(Slider), const Offset(90, 0));
      final rect = tester.getRect(find.byType(Image));
      await tester.dragFrom(
        rect.center - const Offset(40, 0),
        const Offset(80, 0),
      );
      await settle(tester);
      await tester.tap(find.text('消しゴム'));
      await tester.pump();
      await tester.tapAt(rect.center);
      await settle(tester);
      await tester.tap(find.byTooltip('元に戻す'));
      await settle(tester);
      await tester.tap(find.text('キャンセル'));
      await settle(tester);
      expect(result, isNull);
      expect(original.operations, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
