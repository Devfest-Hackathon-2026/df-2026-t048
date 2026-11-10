import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:postcheck/adapters/local_storage.dart';
import 'package:postcheck/application/check_draft.dart';
import 'package:postcheck/domain/models.dart';
import 'package:postcheck/l10n/app_localizations.dart';
import 'package:postcheck/main.dart';
import 'package:postcheck/presentation/photo_preview.dart';
import 'package:postcheck/presentation/photo_viewer.dart';
import 'package:postcheck/presentation/postcheck_controller.dart';

import 'controller_test.dart'
    show TestPerception, TestContext, TestImages, TestExport;
import 'localization_test.dart' show localizedApp;

Uint8List _png(int width, int height) =>
    Uint8List.fromList(img.encodePng(img.Image(width: width, height: height)));

void main() {
  testWidgets('full-screen photo supports pinch, pan, zoom out and reset', (
    tester,
  ) async {
    final original = _png(120, 80);
    final redacted = _png(120, 80);
    await tester.pumpWidget(
      localizedApp(
        Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              child: PhotoPreview(
                photo: PhotoInput(bytes: original, width: 120, height: 80),
                preview: redacted,
                findings: const [],
                decisions: const {},
                selectedId: null,
                drawing: false,
                onSelect: (_) {},
                onDraw: (_) {},
              ),
            ),
          ),
        ),
        'ja',
      ),
    );
    await tester.tap(find.byKey(const ValueKey('photo-canvas')));
    await tester.pumpAndSettle();
    final viewer = find.byType(PhotoViewer);
    // Opening full screen must preserve the current redaction preview.
    expect(tester.widget<PhotoViewer>(viewer).bytes, same(redacted));
    final image = tester.widget<Image>(
      find.descendant(of: viewer, matching: find.byType(Image)),
    );
    expect((image.image as MemoryImage).bytes, same(redacted));
    final interactive = find.byKey(const ValueKey('fullscreen-photo'));
    final transform = tester
        .widget<InteractiveViewer>(interactive)
        .transformationController!;
    final center = tester.getCenter(interactive);
    final first = await tester.startGesture(
      center - const Offset(30, 0),
      pointer: 10,
    );
    final second = await tester.startGesture(
      center + const Offset(30, 0),
      pointer: 11,
    );
    await tester.pump();
    await first.moveTo(center - const Offset(40, 0));
    await second.moveTo(center + const Offset(40, 0));
    await tester.pump();
    await first.moveTo(center - const Offset(100, 0));
    await second.moveTo(center + const Offset(100, 0));
    await tester.pump();
    final enlarged = transform.value.getMaxScaleOnAxis();
    expect(enlarged, greaterThan(1));
    await first.moveTo(center - const Offset(60, 0));
    await second.moveTo(center + const Offset(60, 0));
    await tester.pump();
    expect(transform.value.getMaxScaleOnAxis(), lessThan(enlarged));
    expect(transform.value.getMaxScaleOnAxis(), greaterThan(1));
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    final beforePan = transform.value.clone();
    await tester.drag(interactive, const Offset(40, 25));
    await tester.pumpAndSettle();
    expect(transform.value, isNot(beforePan));
    await tester.tap(find.byTooltip('元の倍率に戻す'));
    await tester.pumpAndSettle();
    expect(transform.value, Matrix4.identity());
    await tester.tap(find.byKey(const ValueKey('close-photo-viewer')));
    await tester.pumpAndSettle();
    expect(viewer, findsNothing);
    expect(find.byType(PhotoPreview), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final language in ['ja', 'en']) {
    testWidgets('draft and review photos open and retain state ($language)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({'ui.language': language});
      final c = PostCheckController(
        check: CheckDraft(perception: TestPerception(), context: TestContext()),
        images: TestImages(),
        exporter: TestExport(),
      );
      addTearDown(c.dispose);
      await c.loadPhoto(_png(100, 100));
      c.setCaption('fixture caption');
      await tester.pumpWidget(
        PostCheckApp(
          controller: c,
          settings: LocalSettings(await SharedPreferences.getInstance()),
          startWithCamera: false,
        ),
      );
      await tester.pumpAndSettle();
      final s = AppStrings(Locale(language));
      final resume = find.text(s.text('作業中の下書きに戻る'));
      await tester.ensureVisible(resume);
      await tester.tap(resume);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(s.text('写真を全画面表示')));
      await tester.pumpAndSettle();
      expect(find.byType(PhotoViewer), findsOneWidget);
      expect(find.text(s.text('2本の指で拡大・縮小、ドラッグで移動')), findsOneWidget);
      // System back closes only the viewer, keeping the draft intact.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(c.caption, 'fixture caption');
      expect(c.photo, isNotNull);
      await tester.tap(find.byKey(const ValueKey('check-button')));
      await tester.pumpAndSettle();
      final report = c.report;
      final selected = c.selectedId;
      final decisions = Map<String, ReviewDecision>.of(c.reviewDecisions);
      await tester.tap(find.byKey(const ValueKey('open-photo-viewer')));
      await tester.pumpAndSettle();
      expect(find.byType(PhotoViewer), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('close-photo-viewer')));
      await tester.pumpAndSettle();
      expect(c.report, same(report));
      expect(c.selectedId, selected);
      expect(c.reviewDecisions, decisions);
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [const Size(60, 240), const Size(240, 60)]) {
    testWidgets('fits $size in a small screen with large English text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        localizedApp(
          PhotoViewer(bytes: _png(size.width.toInt(), size.height.toInt())),
          'en',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close photo').hitTestable(), findsOneWidget);
      expect(find.byTooltip('Reset zoom').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
