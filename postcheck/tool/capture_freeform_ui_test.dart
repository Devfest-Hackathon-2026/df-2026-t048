// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postcheck/adapters/demo_input.dart';
import 'package:postcheck/domain/models.dart';
import 'package:postcheck/presentation/mask_editor.dart';
import 'package:postcheck/presentation/app_theme.dart';
import '../test/mask_editor_test.dart' show EditorImages, settle;

void main() {
  testWidgets('capture real polygon and brush editor with fictional photo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final entry in {
      'Capture': '/tmp/postcheck-ui-NotoSansJP.ttf',
      '.SF Pro Text': '/tmp/postcheck-ui-NotoSansJP.ttf',
      '.SF Pro Display': '/tmp/postcheck-ui-NotoSansJP.ttf',
      'Roboto': '/tmp/postcheck-ui-NotoSansJP.ttf',
      'MaterialIcons':
          '/Users/kawakou/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      'packages/cupertino_icons/CupertinoIcons':
          '/Users/kawakou/.pub-cache/hosted/pub.dev/cupertino_icons-1.0.9/assets/CupertinoIcons.ttf',
    }.entries) {
      final loader = FontLoader(entry.key)
        ..addFont(
          Future.value(
            ByteData.sublistView(File(entry.value).readAsBytesSync()),
          ),
        );
      await tester.runAsync(loader.load);
    }
    final data = await tester.runAsync(
      () => createDemoPhoto(fontFamily: 'Capture'),
    );
    final photo = PhotoInput(
      bytes: data!.buffer.asUint8List(),
      width: 1200,
      height: 800,
    );
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildPostCheckTheme().copyWith(
            textTheme: buildPostCheckTheme().textTheme.apply(
              fontFamily: 'Capture',
            ),
          ),
          home: MaskEditor(
            photo: photo,
            images: EditorImages(),
            style: RedactionStyle.blur,
            initial: PhotoMask([
              MaskOperation(MaskOperationKind.polygon, const [
                MaskPoint(.07, .23),
                MaskPoint(.57, .21),
                MaskPoint(.56, .68),
                MaskPoint(.08, .68),
              ]),
            ]),
          ),
        ),
      ),
    );
    await settle(tester);
    Future<void> shot(String name) async {
      await tester.pumpAndSettle();
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('../output/postcheck-freeform-v12/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    await shot('polygon');
    await tester.tap(find.text('ブラシ'));
    await settle(tester);
    await shot('brush');
    expect(tester.takeException(), isNull);
  });
}
