import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:postcheck/adapters/local_storage.dart';
import 'package:postcheck/domain/model_preparation.dart';
import 'package:postcheck/domain/preferences.dart';
import 'package:postcheck/l10n/app_localizations.dart';
import 'package:postcheck/presentation/app_theme.dart';
import 'package:postcheck/presentation/settings_page.dart';

final _input = find.byKey(const ValueKey('private-word-input'));
final _add = find.byKey(const ValueKey('private-word-add'));

class _DelayedWordSettings implements SettingsPort {
  final saving = Completer<void>();
  List<String> words = [];
  @override
  List<String> get privateWords => words;
  @override
  bool get aiEnabled => false;
  @override
  ReviewPreferences get reviewPreferences => const ReviewPreferences();
  @override
  Future<ModelPreparation> modelPreparation() async =>
      const ModelPreparation(phase: ModelPreparationPhase.unavailable);
  @override
  Future<void> saveWords(String input) async {
    await saving.future;
    words = input.split('\n');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<LocalSettings> _openWords(
  WidgetTester tester, {
  String words = '',
  String locale = 'ja',
}) async {
  SharedPreferences.setMockInitialValues({});
  final settings = LocalSettings(await SharedPreferences.getInstance());
  if (words.isNotEmpty) await settings.saveWords(words);
  await _openWordPanel(tester, settings, locale: locale);
  return settings;
}

Future<void> _openWordPanel(
  WidgetTester tester,
  SettingsPort settings, {
  String locale = 'ja',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildPostCheckTheme(),
      locale: Locale(locale),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStrings.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      home: SettingsPage(settings: settings),
    ),
  );
  await tester.tap(find.text(AppStrings(Locale(locale)).text('登録ワード')));
  await tester.pumpAndSettle();
}

Future<void> _submit(WidgetTester tester, String word) async {
  await tester.enterText(_input, word);
  await tester.tap(_add);
  await tester.pumpAndSettle();
}

Finder _row(String word) => find.byKey(ValueKey('private-word-$word'));

Finder _snack(String text) =>
    find.descendant(of: find.byType(SnackBar), matching: find.text(text));

void main() {
  for (final nextWord in ['企画B', '企画A']) {
    testWidgets('saving preserves edits made during the save ($nextWord)', (
      tester,
    ) async {
      final settings = _DelayedWordSettings();
      await _openWordPanel(tester, settings);
      await tester.enterText(_input, '企画A');
      await tester.tap(_add);
      await tester.pump();
      expect(tester.widget<TextField>(_input).enabled, isNot(false));
      expect(settings.privateWords, isEmpty);

      // Editing away and back to the submitted text is still a newer input.
      await tester.enterText(_input, '入力途中');
      await tester.enterText(_input, nextWord);
      settings.saving.complete();
      await tester.pumpAndSettle();

      expect(settings.privateWords, ['企画A']);
      expect(_snack('「企画A」を追加しました'), findsOneWidget);
      expect(tester.widget<TextField>(_input).controller!.text, nextWord);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('adding a word lists it, persists it and reports the result', (
    tester,
  ) async {
    final settings = await _openWords(tester);
    expect(find.text('まだ登録されていません'), findsOneWidget);
    expect(find.text('登録したワードはこの端末内に保存され、クラウドAIへは送信しません。'), findsOneWidget);

    await _submit(tester, '  試作A ');

    expect(settings.privateWords, ['試作A']);
    expect(_row('試作A'), findsOneWidget);
    expect(_snack('「試作A」を追加しました'), findsOneWidget);
    expect(find.text('まだ登録されていません'), findsNothing);
    // The input is cleared so the next word can be typed immediately.
    expect(tester.widget<TextField>(_input).controller!.text, isEmpty);
    // A fresh adapter reads the same on-device store.
    final reread = LocalSettings(await SharedPreferences.getInstance());
    expect(reread.privateWords, ['試作A']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard done adds the word without the button', (tester) async {
    final settings = await _openWords(tester);
    await tester.enterText(_input, '社外秘');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(settings.privateWords, ['社外秘']);
    expect(_snack('「社外秘」を追加しました'), findsOneWidget);
  });

  testWidgets('consecutive additions each show their own result', (
    tester,
  ) async {
    final settings = await _openWords(tester);
    await _submit(tester, '企画A');
    expect(_snack('「企画A」を追加しました'), findsOneWidget);
    await _submit(tester, '企画B');
    expect(_snack('「企画B」を追加しました'), findsOneWidget);
    expect(_snack('「企画A」を追加しました'), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(settings.privateWords, ['企画A', '企画B']);
    expect(_row('企画A'), findsOneWidget);
    expect(_row('企画B'), findsOneWidget);
  });

  testWidgets('deleting removes the word from the list and storage', (
    tester,
  ) async {
    final settings = await _openWords(tester, words: '残す語\n消す語');
    expect(_row('消す語'), findsOneWidget);
    await tester.tap(find.byTooltip('「消す語」を削除'));
    await tester.pumpAndSettle();
    expect(settings.privateWords, ['残す語']);
    expect(_row('消す語'), findsNothing);
    expect(_row('残す語'), findsOneWidget);
    expect(_snack('「消す語」を削除しました'), findsOneWidget);
    // No confirmation dialog: the action is immediate and reported.
    expect(find.byType(CupertinoAlertDialog), findsNothing);
  });

  testWidgets('duplicates are reported and not added twice', (tester) async {
    final settings = await _openWords(tester);
    await _submit(tester, '試作A');
    await _submit(tester, '試作A');
    expect(settings.privateWords, ['試作A']);
    expect(_row('試作A'), findsOneWidget);
    expect(_snack('「試作A」はすでに登録されています'), findsOneWidget);
    expect(_snack('「試作A」を追加しました'), findsNothing);
  });

  testWidgets('empty input saves nothing and asks for a word', (tester) async {
    final settings = await _openWords(tester);
    await _submit(tester, '   ');
    expect(settings.privateWords, isEmpty);
    expect(_snack('追加するワードを入力してください'), findsOneWidget);
  });

  testWidgets('comma-separated input keeps the existing normalisation', (
    tester,
  ) async {
    final settings = await _openWords(tester);
    await _submit(tester, '企画A、企画B');
    expect(settings.privateWords, ['企画A', '企画B']);
    expect(_snack('2件追加しました'), findsOneWidget);
  });

  testWidgets('length and count limits show the storage message', (
    tester,
  ) async {
    const limit = '登録ワードは500件、1件200文字までです。';
    final settings = await _openWords(tester);
    await _submit(tester, 'あ' * 201);
    expect(settings.privateWords, isEmpty);
    expect(_snack(limit), findsOneWidget);
    // The rejected text stays in the field so it can be corrected.
    expect(tester.widget<TextField>(_input).controller!.text, 'あ' * 201);

    await settings.saveWords([for (var i = 0; i < 500; i++) 'w$i'].join('\n'));
    await _submit(tester, '501件目');
    expect(settings.privateWords, hasLength(500));
    expect(settings.privateWords, isNot(contains('501件目')));
    expect(_snack(limit), findsOneWidget);
  });

  testWidgets('English renders the word panel without Japanese leftovers', (
    tester,
  ) async {
    final settings = await _openWords(tester, locale: 'en');
    expect(find.text('Registered words'), findsOneWidget);
    expect(find.text('No words yet'), findsOneWidget);
    expect(
      find.text(
        'Registered words are kept on this device and are not sent to cloud AI.',
      ),
      findsOneWidget,
    );
    expect(find.text('Add'), findsOneWidget);
    await _submit(tester, 'Sakura');
    expect(settings.privateWords, ['Sakura']);
    expect(_snack('Added “Sakura”'), findsOneWidget);
    await _submit(tester, 'Sakura');
    expect(_snack('“Sakura” is already registered'), findsOneWidget);
    await _submit(tester, '');
    expect(_snack('Enter a word to add'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete “Sakura”'));
    await tester.pumpAndSettle();
    expect(_snack('Deleted “Sakura”'), findsOneWidget);
    expect(settings.privateWords, isEmpty);

    const s = AppStrings(Locale('en'));
    for (final source in [
      '企画名など、公開前に確認したい言葉を1件ずつ追加します。',
      '例：Project Sakura',
      '追加できませんでした',
      '3件追加しました',
      '登録ワードは500件、1件200文字までです。',
    ]) {
      expect(s.text(source), isNot(source), reason: source);
    }
    // Registered words inside messages stay literal, even if they look like
    // an authored label.
    expect(s.text('「削除」を追加しました'), 'Added “削除”');
    expect(tester.takeException(), isNull);
  });
}
