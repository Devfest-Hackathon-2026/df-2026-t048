import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:postcheck/l10n/app_localizations.dart';
import 'package:postcheck/l10n/english.dart';
import 'package:postcheck/main.dart';
import 'package:postcheck/adapters/local_storage.dart';
import 'package:postcheck/application/check_draft.dart';
import 'package:postcheck/application/ai_contract.dart';
import 'package:postcheck/domain/models.dart';
import 'package:postcheck/presentation/postcheck_controller.dart';
import 'package:postcheck/presentation/venue_page.dart';
import 'package:postcheck_rules/postcheck_rules.dart';
import 'controller_test.dart'
    show TestPerception, TestContext, TestImages, TestExport;

Widget englishApp(Widget child) => localizedApp(child, 'en');
Widget localizedApp(Widget child, String code) => MaterialApp(
  locale: Locale(code),
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStrings.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  home: child,
);
PostCheckController controller() => PostCheckController(
  check: CheckDraft(perception: TestPerception(), context: TestContext()),
  images: TestImages(),
  exporter: TestExport(),
);
void main() {
  for (final removedCode in ['zh', 'ko']) {
    for (final (deviceCode, expectedLabel) in [
      ('ja', '写真を選ぶ'),
      ('ko', 'Choose photo'),
    ]) {
      testWidgets('saved $removedCode falls back on $deviceCode devices', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({'ui.language': removedCode});
        tester.platformDispatcher.localesTestValue = [Locale(deviceCode)];
        addTearDown(tester.platformDispatcher.clearLocalesTestValue);
        final c = controller();
        addTearDown(c.dispose);
        await tester.pumpWidget(
          PostCheckApp(
            controller: c,
            settings: LocalSettings(await SharedPreferences.getInstance()),
            startWithCamera: false,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(expectedLabel), findsOneWidget);
        expect(AppLanguage.valid(removedCode), isNull);
        expect(AppStrings.delegate.isSupported(Locale(removedCode)), isFalse);
        final strings = AppStrings(Locale(deviceCode == 'ja' ? 'ja' : 'en'));
        await tester.tap(find.byTooltip(strings.text('設定')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(strings.text('言語')));
        await tester.pumpAndSettle();
        expect(find.text('日本語'), findsWidgets);
        expect(find.text('English'), findsWidgets);
        expect(find.text('中文（简体）'), findsNothing);
        expect(find.text('한국어'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
  test(
    'local AI prompt requests English questions while retaining source quotes',
    () {
      expect(contextSystemPromptFor('en'), contains('英語の短い質問'));
      expect(contextSystemPromptFor('en'), contains('原文どおりのcaptionQuote'));
      expect(contextSystemPromptFor('ja'), contextSystemPrompt);
    },
  );

  test(
    'catalog translates authored templates while preserving quoted private words',
    () {
      const s = AppStrings(Locale('en'));
      expect(
        s.text('場所のルール · ON · 手動選択'),
        'Place rules · ON · selected manually',
      );
      expect(
        s.text('登録ワード「撮影」が写っています。公開して大丈夫ですか？'),
        'The private word “撮影” is visible. Is it OK to share?',
      );
      expect(
        s.text('人物が写っています。公開する範囲を確認してください。'),
        'People may be visible. Check what you share.',
      );
      expect(s.text('あと3件を確認'), '3 items left to review');
      expect(s.text('未登録の原文'), '未登録の原文');
      for (final entry in english.entries) {
        final sourceSlots = RegExp(
          r'\{\d+\}',
        ).allMatches(entry.key).map((m) => m[0]).toSet();
        final targetSlots = RegExp(
          r'\{\d+\}',
        ).allMatches(entry.value).map((m) => m[0]).toSet();
        expect(targetSlots, sourceSlots, reason: entry.key);
        expect(entry.value, isNotEmpty);
      }
    },
  );
  test('English contact and embargo checks use correct caption ranges', () {
    const caption =
        '🎨 CONFIDENTIAL — call +44 20 7946 0958 or +1 (415) 555-0123, test@example.com';
    final results = const RuleChecker().check(
      const DraftInput(caption: caption),
      const Observations(),
    );
    for (final expected in [
      '+44 20 7946 0958',
      '+1 (415) 555-0123',
      'test@example.com',
      'CONFIDENTIAL',
    ]) {
      final finding = results.singleWhere((f) => f.excerpt == expected);
      final range = (finding.target as CaptionTarget).range;
      expect(caption.substring(range.start, range.end), expected);
    }
    expect(
      const RuleChecker().check(
        const DraftInput(
          caption: 'Gallery opens 2026-11-08 at 10:00. Ticket 12345678.',
        ),
        const Observations(),
      ),
      isEmpty,
    );
  });
  for (final code in ['en']) {
    final strings = AppStrings(Locale(code));
    testWidgets(
      '$code changes inside settings, persists, and keeps current route',
      (tester) async {
        SharedPreferences.setMockInitialValues({'ui.language': 'ja'});
        final prefs = await SharedPreferences.getInstance();
        final c = controller();
        addTearDown(c.dispose);
        await tester.pumpWidget(
          PostCheckApp(
            controller: c,
            settings: LocalSettings(prefs),
            startWithCamera: false,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('設定'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('言語'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(AppStrings.languageNames[code]!));
        await tester.pumpAndSettle();
        expect(find.text(strings.text('言語')), findsOneWidget);
        expect(find.text(strings.text('登録ワード')), findsOneWidget);
        expect(prefs.getString('ui.language'), code);
        await tester.tap(find.byTooltip(strings.text('戻る')));
        await tester.pumpAndSettle();
        expect(find.text(strings.text('写真を選ぶ')), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          PostCheckApp(
            controller: c,
            settings: LocalSettings(prefs),
            startWithCamera: false,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(strings.text('写真を選ぶ')), findsOneWidget);
        await tester.tap(find.byTooltip(strings.text('設定')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(strings.text('言語')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(strings.text('端末に合わせる')));
        await tester.pumpAndSettle();
        expect(prefs.containsKey('ui.language'), isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'device locale selects Japanese; Chinese and Korean fall back to English',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final c = controller();
      addTearDown(c.dispose);
      tester.platformDispatcher.localesTestValue = [const Locale('fr')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(
        PostCheckApp(
          controller: c,
          settings: LocalSettings(await SharedPreferences.getInstance()),
          startWithCamera: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Choose photo'), findsOneWidget);
      tester.platformDispatcher.localesTestValue = [const Locale('ja')];
      await tester.pumpAndSettle();
      expect(find.text('写真を選ぶ'), findsOneWidget);
      for (final locale in [
        const Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hans',
          countryCode: 'CN',
        ),
        const Locale('zh', 'TW'),
        const Locale('ko', 'KR'),
      ]) {
        tester.platformDispatcher.localesTestValue = [locale];
        await tester.pumpAndSettle();
        expect(find.text('Choose photo'), findsOneWidget);
      }
    },
  );
  for (final code in ['en']) {
    final strings = AppStrings(Locale(code));
    testWidgets(
      '$code museum rule summary preserves original evidence on a small screen',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.4;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final venue = (await const DemoVenueRepository().list()).first;
        await tester.pumpWidget(
          localizedApp(VenueRulesPage(venue: venue, canApply: true), code),
        );
        await tester.pumpAndSettle();
        expect(find.text(strings.text('施設のルール')), findsOneWidget);
        expect(find.text(venue.policy.name), findsOneWidget);
        expect(find.text(strings.text('撮影')), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text(strings.text('ルールの原文')).hitTestable(),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text(strings.text('ルールの原文')).hitTestable());
        await tester.pumpAndSettle();
        expect(find.text(venue.policy.sourceText), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
