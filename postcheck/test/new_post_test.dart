import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:postcheck/adapters/local_storage.dart';
import 'package:postcheck/application/check_draft.dart';
import 'package:postcheck/l10n/app_localizations.dart';
import 'package:postcheck/main.dart';
import 'package:postcheck/presentation/postcheck_controller.dart';
import 'controller_test.dart'
    show TestPerception, TestContext, TestImages, TestExport;

Future<PostCheckController> _pumpApp(
  WidgetTester tester, {
  String language = 'ja',
  bool withDraft = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({'ui.language': language});
  final controller = PostCheckController(
    languageCode: () => language,
    check: CheckDraft(perception: TestPerception(), context: TestContext()),
    images: TestImages(),
    exporter: TestExport(),
  );
  addTearDown(controller.dispose);
  if (withDraft) {
    // A decodable photo: the draft screen renders it.
    await controller.loadPhoto(
      Uint8List.fromList(img.encodePng(img.Image(width: 4, height: 4))),
    );
    controller.setCaption('前の投稿文');
  }
  await tester.pumpWidget(
    PostCheckApp(
      controller: controller,
      settings: LocalSettings(await SharedPreferences.getInstance()),
      startWithCamera: false,
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

String _captionField(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const ValueKey('caption-input')))
    .controller!
    .text;

void main() {
  final strings = AppStrings(const Locale('ja'));

  testWidgets('text-only start without a draft opens an empty draft', (
    tester,
  ) async {
    final c = await _pumpApp(tester);
    await _tapVisible(tester, find.byKey(const ValueKey('text-only-button')));
    expect(find.byKey(const ValueKey('start-fresh-button')), findsNothing);
    expect(find.byKey(const ValueKey('caption-input')), findsOneWidget);
    expect(c.photo, isNull);
  });

  testWidgets('text-only start can drop the previous photo and caption', (
    tester,
  ) async {
    final c = await _pumpApp(tester, withDraft: true);
    await _tapVisible(tester, find.byKey(const ValueKey('text-only-button')));
    expect(find.text(strings.text('作業中の下書きがあります')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('start-fresh-button')));
    await tester.pumpAndSettle();
    expect(c.photo, isNull);
    expect(c.caption, isEmpty);
    expect(_captionField(tester), isEmpty);
  });

  testWidgets('choosing to continue keeps the previous draft', (tester) async {
    final c = await _pumpApp(tester, withDraft: true);
    await _tapVisible(tester, find.byKey(const ValueKey('text-only-button')));
    await tester.tap(find.byKey(const ValueKey('continue-draft-button')));
    await tester.pumpAndSettle();
    expect(c.photo, isNotNull);
    expect(c.caption, '前の投稿文');
    expect(_captionField(tester), '前の投稿文');
  });

  testWidgets('dismissing the question changes nothing', (tester) async {
    final c = await _pumpApp(tester, withDraft: true);
    await _tapVisible(tester, find.byKey(const ValueKey('text-only-button')));
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('caption-input')), findsNothing);
    expect(c.photo, isNotNull);
    expect(c.caption, '前の投稿文');
  });

  for (final language in ['ja', 'en']) {
    testWidgets('finished screen offers a new post ($language)', (
      tester,
    ) async {
      final s = AppStrings(Locale(language));
      final c = await _pumpApp(tester, language: language);
      await _tapVisible(tester, find.byKey(const ValueKey('text-only-button')));
      await tester.enterText(
        find.byKey(const ValueKey('caption-input')),
        '連絡先 taro@example.com',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('check-button')));
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.text(s.text('残す')).hitTestable());
      await tester.tap(find.byKey(const ValueKey('preview-button')));
      await tester.pumpAndSettle();
      expect(c.canExport, isTrue);

      await _tapVisible(tester, find.byKey(const ValueKey('new-post-button')));
      expect(find.text(s.text('新しい投稿を始めますか？')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirm-new-post-button')));
      await tester.pumpAndSettle();

      expect(c.caption, isEmpty);
      expect(c.photo, isNull);
      expect(c.report, isNull);
      expect(find.byKey(const ValueKey('library-button')), findsOneWidget);
      // Starting text-only again must not ask about, or carry, the old post.
      await _tapVisible(tester, find.byKey(const ValueKey('text-only-button')));
      expect(find.byKey(const ValueKey('start-fresh-button')), findsNothing);
      expect(_captionField(tester), isEmpty);
    });
  }
}
