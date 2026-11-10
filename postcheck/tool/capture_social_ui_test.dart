// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:image/image.dart' as img;
import 'package:postcheck/adapters/social_share.dart';
import 'package:postcheck/adapters/story_image.dart';
import 'package:postcheck/application/check_draft.dart';
import 'package:postcheck/domain/models.dart';
import 'package:postcheck/domain/social_share.dart';
import 'package:postcheck/presentation/app_theme.dart';
import 'package:postcheck/presentation/social_share_sheet.dart';
import 'package:postcheck/presentation/story_share_page.dart';
import 'package:postcheck/presentation/postcheck_controller.dart';
import 'package:postcheck/l10n/app_localizations.dart';
import '../test/controller_test.dart'
    show TestImages, TestExport, TestPerception, TestContext;

void main() {
  testWidgets(
    'capture implemented social menu and rendered story with synthetic art',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final entry in {
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
      final photo = img.Image(width: 900, height: 1200);
      img.fill(photo, color: img.ColorRgb8(232, 225, 214));
      img.fillRect(
        photo,
        x1: 110,
        y1: 180,
        x2: 790,
        y2: 970,
        color: img.ColorRgb8(53, 48, 43),
      );
      img.fillRect(
        photo,
        x1: 140,
        y1: 210,
        x2: 760,
        y2: 940,
        color: img.ColorRgb8(73, 111, 124),
      );
      img.fillCircle(
        photo,
        x: 580,
        y: 420,
        radius: 115,
        color: img.ColorRgb8(224, 171, 91),
      );
      img.fillRect(
        photo,
        x1: 140,
        y1: 690,
        x2: 760,
        y2: 940,
        color: img.ColorRgb8(38, 65, 70),
      );
      final photoPng = Uint8List.fromList(img.encodePng(photo));
      final data = await tester.runAsync(
        () => const StoryImageComposer().compose(
          ExportArtifact(
            caption: 'A quiet moment at the museum.\nChecked before sharing.',
            imageBytes: photoPng,
          ),
          StoryLayout.card,
        ),
      );
      final out = Directory('../output/postcheck-social-v14');
      out.createSync(recursive: true);
      File('${out.path}/story-image.png').writeAsBytesSync(data!);
      final controller = PostCheckController(
        check: CheckDraft(perception: TestPerception(), context: TestContext()),
        images: TestImages(),
        exporter: TestExport(),
        socialExporter: SocialShareAdapter(renderStory: (_, _) async => data),
      );
      addTearDown(controller.dispose);
      controller.setCaption('A quiet moment at the museum.');
      await controller.loadPhoto(photoPng);
      await controller.runCheck([]);
      for (final finding in controller.findings) {
        await controller.decide(finding, ReviewDecision.keep);
      }
      final key = GlobalKey();
      Widget app(Widget home, String language) => RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildPostCheckTheme(),
          locale: Locale(language),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: home,
        ),
      );
      Future<void> shot(String name) async {
        await tester.pumpAndSettle();
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '${out.path}/$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await tester.pumpWidget(
        app(
          const Scaffold(
            body: SafeArea(child: SocialShareSheet(hasPhoto: true)),
          ),
          'ja',
        ),
      );
      await shot('share-menu-ja');
      await tester.runAsync(
        () => precacheImage(
          MemoryImage(data),
          tester.element(find.byType(Scaffold)),
        ),
      );
      await tester.pumpWidget(
        app(StorySharePage(controller: controller), 'en'),
      );
      await shot('story-preview-en');
      expect(tester.takeException(), isNull);
    },
  );
}
