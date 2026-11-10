// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:postcheck/adapters/downloaded_gemma.dart';
import 'package:postcheck/adapters/local_storage.dart';
import 'package:postcheck/l10n/app_localizations.dart';
import 'package:postcheck/presentation/app_theme.dart';
import 'package:postcheck/presentation/settings_page.dart';

// Render only synthetic progress. This never downloads a model or uses a photo.
void main() {
  testWidgets('capture numeric model download progress', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
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
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      DownloadedGemma.channel,
      (_) async => {
        'phase': 'downloading',
        'received': DownloadedGemma.size ~/ 2,
      },
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(DownloadedGemma.channel, null),
    );
    final settings = LocalSettings(await SharedPreferences.getInstance());
    for (final language in ['ja', 'en']) {
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
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
            home: SettingsPage(settings: settings),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text(language == 'ja' ? '端末内AI' : 'On-device AI'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('../output/postcheck-model-progress/$language.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
