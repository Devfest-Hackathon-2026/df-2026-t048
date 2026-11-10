// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:postcheck/adapters/demo_input.dart';
import 'package:postcheck/adapters/local_storage.dart';
import 'package:postcheck/application/check_draft.dart';
import 'package:postcheck/domain/models.dart';
import 'package:postcheck/domain/ports.dart';
import 'package:postcheck/domain/input.dart';
import 'package:postcheck/presentation/app_theme.dart';
import 'package:postcheck/presentation/home_page.dart';
import 'package:postcheck/presentation/postcheck_controller.dart';
import 'package:postcheck/l10n/app_localizations.dart';
import '../test/controller_test.dart' show TestExport, TestContext;

class ReviewCapturePerception implements PerceptionPort {
  @override
  Future<Observations> inspect(PhotoInput photo) async => const Observations(
    blocks: [
      TextBlock(
        id: 'project',
        text: '新企画の資料',
        region: ImageRegion(.108, .25, .3, .06),
      ),
      TextBlock(
        id: 'title',
        text: 'Project Sakura',
        region: ImageRegion(.108, .331, .35, .06),
      ),
      TextBlock(
        id: 'name',
        text: '山田 太郎',
        region: ImageRegion(.683, .406, .22, .06),
      ),
      TextBlock(
        id: 'email',
        text: 'taro@example.com',
        region: ImageRegion(.675, .506, .28, .05),
      ),
    ],
  );
}

class FixturePhoto implements PhotoLibraryPort, ImageProcessingPort {
  FixturePhoto(this.png);
  final Uint8List png;
  @override
  Future<Uint8List?> pick() async => png;
  @override
  Future<Uint8List?> sample() async => png;
  @override
  Future<PhotoInput> prepare(Uint8List bytes) async =>
      PhotoInput(bytes: png, width: 1200, height: 800);
  @override
  Future<Uint8List> redact(
    PhotoInput photo,
    List<PhotoMask> masks, {
    RedactionStyle style = RedactionStyle.black,
  }) async => png;
}

void main() {
  testWidgets('capture implemented vertical review with synthetic OCR fixtures', (
    tester,
  ) async {
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
    final data = await tester.runAsync(
      () => createDemoPhoto(fontFamily: '.SF Pro Text'),
    );
    final photo = FixturePhoto(data!.buffer.asUint8List());
    SharedPreferences.setMockInitialValues({});
    final settings = LocalSettings(await SharedPreferences.getInstance());
    final c = PostCheckController(
      check: CheckDraft(
        perception: ReviewCapturePerception(),
        context: TestContext(),
      ),
      images: photo,
      exporter: TestExport(),
      settings: settings,
    );
    addTearDown(c.dispose);
    final key = GlobalKey();
    Widget app(String lang) => RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildPostCheckTheme(),
        locale: Locale(lang),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        home: HomePage(
          controller: c,
          settings: settings,
          library: photo,
          openCamera: (_) async => null,
        ),
      ),
    );
    await tester.pumpWidget(app('ja'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('library-button')));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => precacheImage(
        MemoryImage(photo.png),
        tester.element(find.byType(Scaffold)),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('check-button')));
    await tester.pumpAndSettle();
    Future<void> shot(String name) async {
      await tester.pumpAndSettle();
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('../output/postcheck-review-list-v15/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await shot('review-list-ja');
    await tester.ensureVisible(
      find.byKey(const ValueKey('finding-select-block-name')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('finding-select-block-name')));
    await tester.pumpAndSettle();
    expect(c.selectedId, 'block-name');
    await shot('selected-text-ja');
    await tester.pumpWidget(app('en'));
    await shot('selected-text-en');
    expect(tester.takeException(), isNull);
  });
}
