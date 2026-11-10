import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:postcheck/adapters/local_storage.dart';
import 'package:postcheck/application/check_draft.dart';
import 'package:postcheck/application/review.dart';
import 'package:postcheck/main.dart';
import 'package:postcheck/l10n/app_localizations.dart';
import 'package:postcheck/presentation/postcheck_controller.dart';
import 'controller_test.dart'
    show TestPerception, TestContext, TestImages, TestExport;

void main() {
  for (final language in ['ja', 'en']) {
    final strings = AppStrings(Locale(language));
    for (final size in [const Size(390, 844), const Size(320, 568)]) {
      testWidgets('caption → check → decide → export at $size ($language)', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        if (size.width == 320) {
          tester.platformDispatcher.textScaleFactorTestValue = 1.4;
        }
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({'ui.language': language});
        final controller = PostCheckController(
          languageCode: () => language,
          check: CheckDraft(
            perception: TestPerception(),
            context: TestContext(),
          ),
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
        await tester.scrollUntilVisible(
          find.text(strings.text('文章だけチェックする')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text(strings.text('文章だけチェックする')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(strings.text('文章だけチェックする')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('caption-input')),
          '連絡先 taro@example.com',
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('check-button')),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('check-button')));
        await tester.pumpAndSettle();
        expect(controller.findings.length, 1);
        await tester.scrollUntilVisible(
          find.text(strings.text('隠す')).hitTestable(),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text(strings.text('隠す')));
        await tester.pumpAndSettle();
        expect(controller.outputCaption, '連絡先 ${redactionMarkerFor(language)}');
        expect(controller.canExport, isFalse);
        await tester.ensureVisible(
          find.byKey(const ValueKey('recheck-button')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('recheck-button')));
        await tester.pumpAndSettle();
        expect(controller.canExport, isTrue);
        await tester.ensureVisible(
          find.byKey(const ValueKey('preview-button')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('preview-button')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const ValueKey('export-button')));
        await tester.pumpAndSettle();
        final button = tester.widget<FilledButton>(
          find.byKey(const ValueKey('export-button')),
        );
        expect(button.onPressed, isNotNull);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
