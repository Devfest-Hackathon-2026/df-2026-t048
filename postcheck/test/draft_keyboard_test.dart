import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:postcheck/adapters/local_storage.dart';
import 'package:postcheck/application/check_draft.dart';
import 'package:postcheck/l10n/app_localizations.dart';
import 'package:postcheck/main.dart';
import 'package:postcheck/presentation/postcheck_controller.dart';
import 'controller_test.dart'
    show TestPerception, TestContext, TestImages, TestExport;

const _screen = Size(390, 844);
const _keyboard = 320.0;

Future<PostCheckController> _openCaptionDraft(
  WidgetTester tester,
  String language,
) async {
  tester.view.physicalSize = _screen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  SharedPreferences.setMockInitialValues({'ui.language': language});
  final controller = PostCheckController(
    languageCode: () => language,
    check: CheckDraft(perception: TestPerception(), context: TestContext()),
    images: TestImages(),
    exporter: TestExport(),
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    PostCheckApp(
      controller: controller,
      settings: LocalSettings(await SharedPreferences.getInstance()),
      startWithCamera: false,
    ),
  );
  final strings = AppStrings(Locale(language));
  final textOnly = find.text(strings.text('文章だけチェックする'));
  await tester.scrollUntilVisible(
    textOnly,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(textOnly);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('caption-input')),
    '連絡先 taro@example.com',
  );
  await tester.pumpAndSettle();
  return controller;
}

bool _captionFocused(WidgetTester tester) => tester
    .state<EditableTextState>(find.byType(EditableText))
    .widget
    .focusNode
    .hasFocus;

void main() {
  for (final language in ['ja', 'en']) {
    final strings = AppStrings(Locale(language));

    testWidgets('check button stays above the keyboard ($language)', (
      tester,
    ) async {
      final controller = await _openCaptionDraft(tester, language);
      tester.view.viewInsets = const FakeViewPadding(bottom: _keyboard);
      await tester.pumpAndSettle();

      final button = find.byKey(const ValueKey('check-button'));
      expect(
        tester.getRect(button).bottom,
        lessThanOrEqualTo(_screen.height - _keyboard),
      );
      await tester.tap(button.hitTestable());
      await tester.pumpAndSettle();
      expect(controller.findings, hasLength(1));
    });

    testWidgets('tapping outside the caption closes the keyboard ($language)', (
      tester,
    ) async {
      await _openCaptionDraft(tester, language);
      expect(_captionFocused(tester), isTrue);

      await tester.tap(find.text(strings.text('投稿文（任意）')));
      await tester.pumpAndSettle();
      expect(_captionFocused(tester), isFalse);
    });

    testWidgets(
      'caption explains that text is kept automatically ($language)',
      (tester) async {
        await _openCaptionDraft(tester, language);
        expect(find.text(strings.text('入力した文章は自動で保持されます。')), findsOneWidget);
      },
    );
  }
}
