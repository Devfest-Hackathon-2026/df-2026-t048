// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:postcheck/adapters/local_storage.dart';
import 'package:postcheck/application/check_draft.dart';
import 'package:postcheck/main.dart';
import 'package:postcheck/adapters/image_processing.dart';
import 'package:postcheck/adapters/demo_input.dart';
import 'package:postcheck/domain/models.dart';
import 'package:postcheck/domain/ports.dart';
import 'package:postcheck/presentation/postcheck_controller.dart';
import 'package:postcheck/presentation/nearby_controller.dart';
import '../test/controller_test.dart' show TestContext, TestExport;
import '../test/nearby_controller_test.dart' show Repository, GPS;

// Matches createDemoPhoto's fictional badge, not device OCR evidence.
class CapturePerception implements PerceptionPort {
  @override
  Future<Observations> inspect(PhotoInput photo) async => const Observations(
    blocks: [
      TextBlock(
        id: 'badge-email',
        text: 'taro@example.com',
        region: ImageRegion(.67, .50, .26, .06),
      ),
    ],
  );
}

void main() {
  testWidgets('render actual mobile UI with fictional fixtures', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final family in [
      'Notion Sans',
      '.SF Pro Text',
      '.SF Pro Display',
      'Roboto',
    ]) {
      final loader = FontLoader(family);
      loader.addFont(
        Future.value(
          ByteData.sublistView(
            File('/tmp/postcheck-ui-NotoSansJP.ttf').readAsBytesSync(),
          ),
        ),
      );
      await tester.runAsync(loader.load);
    }
    for (final entry in {
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
    final c = PostCheckController(
      check: CheckDraft(
        perception: CapturePerception(),
        context: TestContext(),
      ),
      images: const RasterImageAdapter(),
      exporter: TestExport(),
    );
    final n = NearbyController(
      repository: Repository(),
      location: GPS(),
      demo: true,
    );
    final key = GlobalKey();
    const stage = String.fromEnvironment(
      'CAPTURE_STAGE',
      defaultValue: 'before',
    );
    Future<void> shot(String name) async {
      await tester.pumpAndSettle();
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final im = await boundary.toImage(pixelRatio: 2);
        final bytes = await im.toByteData(format: ui.ImageByteFormat.png);
        final file = File('../output/postcheck-ui-apple-v7/$stage-$name.png');
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        im.dispose();
      });
    }

    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: PostCheckApp(
          controller: c,
          settings: LocalSettings(await SharedPreferences.getInstance()),
          nearby: n,
          startWithCamera: false,
        ),
      ),
    );
    await shot('home');
    await tester.tap(find.byTooltip('設定'));
    await shot('settings');
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('文章だけチェックする'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('文章だけチェックする'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('caption-input')),
      'イベントの準備中。連絡先 taro@example.com',
    );
    await shot('draft');
    await tester.ensureVisible(find.byKey(const ValueKey('check-button')));
    await tester.tap(find.byKey(const ValueKey('check-button')));
    await shot('review');
    final sample = await tester.runAsync(
      () => createDemoPhoto(fontFamily: '.SF Pro Text'),
    );
    await tester.runAsync(() => c.loadPhoto(sample!.buffer.asUint8List()));
    await tester.tap(find.byTooltip('戻る'));
    await shot('photo-draft');
    await tester.tap(find.byKey(const ValueKey('check-button')));
    await shot('photo-review');
    final photoFinding = c.findings.firstWhere((f) => f.target is PhotoTarget);
    await tester.runAsync(() => c.decide(photoFinding, ReviewDecision.hide));
    expect(c.previewBytes, isNotNull, reason: c.error);
    await tester.runAsync(
      () => precacheImage(MemoryImage(c.previewBytes!), key.currentContext!),
    );
    await shot('photo-blur');
    await tester.scrollUntilVisible(
      find.text('範囲を隠す'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('範囲を隠す'));
    await shot('mask-editor');
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    for (final f in c.findings) {
      await c.decide(f, ReviewDecision.keep);
    }
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('preview-button')));
    await shot('export');
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    n.dispose();
    expect(tester.takeException(), isNull);
  });
}
