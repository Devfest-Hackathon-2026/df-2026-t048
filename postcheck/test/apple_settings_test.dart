import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:postcheck/adapters/local_storage.dart';
import 'package:postcheck/presentation/settings_page.dart';
import 'package:postcheck/presentation/app_theme.dart';

void main() {
  testWidgets(
    'grouped settings add words on a small screen and leave without a discard prompt',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      SharedPreferences.setMockInitialValues({});
      final settings = LocalSettings(await SharedPreferences.getInstance());
      await tester.pumpWidget(
        MaterialApp(
          theme: buildPostCheckTheme(),
          home: SettingsPage(settings: settings),
        ),
      );
      expect(find.text('登録ワード'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('登録ワード'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('private-word-input')),
        '試作A',
      );
      await tester.tap(find.byKey(const ValueKey('private-word-add')));
      await tester.pumpAndSettle();
      expect(settings.privateWords, ['試作A']);
      // Words persist on add, so a half-typed entry needs no discard prompt.
      await tester.enterText(
        find.byKey(const ValueKey('private-word-input')),
        '追加しない語',
      );
      await tester.tap(find.byTooltip('戻る'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoAlertDialog), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('1件'), findsOneWidget);
      expect(settings.privateWords, ['試作A']);
      expect(tester.takeException(), isNull);
    },
  );
}
