import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postcheck/l10n/app_localizations.dart';
import 'package:postcheck/presentation/venue_page.dart';
import 'package:postcheck_rules/postcheck_rules.dart';
import 'localization_test.dart' show localizedApp;

const explanations = {
  'en':
      'Photos only in the first-floor lobby. No flash or video. Credit required.',
};
const areas = {'en': 'First floor'};
VenuePolicy policy({bool reviewed = true}) {
  const base = VenuePolicy(
    name: '架空展示館',
    area: '1階',
    areaKind: VenueArea.lobby,
    conditionCodes: ['noFlash', 'photosOnly', 'creditRequired'],
    photography: RulePermission.conditional,
    publication: RulePermission.conditional,
    commercial: RulePermission.forbidden,
    sourceText: '1階ロビーのみ写真撮影可。フラッシュ・動画は禁止。公開時はクレジットを表記してください。',
  );
  return VenuePolicy.fromJson({
    ...base.toJson(),
    'translations': {
      for (final e in explanations.entries)
        e.key: RuleTranslation(
          text: e.value,
          area: areas[e.key]!,
          reviewedDigest: reviewed
              ? base.translationDigest(
                  e.key,
                  RuleTranslation(text: e.value, area: areas[e.key]!),
                )
              : '',
        ).toJson(),
    },
  });
}

Widget screen(VenuePolicy p, String code) => localizedApp(
  VenueRulesPage(
    canApply: true,
    venue: PublishedVenue(
      id: 'fictional',
      version: 1,
      updatedAt: DateTime.utc(2026, 11, 9),
      policy: p,
    ),
  ),
  code,
);

void main() {
  for (final code in ['ja', 'en']) {
    testWidgets(
      '$code shows specific conditions, area, explanation and original at 320px',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.4;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final p = policy();
        final s = AppStrings(Locale(code));
        await tester.pumpWidget(screen(p, code));
        await tester.pumpAndSettle();
        expect(find.text('架空展示館'), findsOneWidget);
        expect(
          find.text('${s.text('フラッシュ禁止')}\n${s.text('写真のみ・動画撮影不可')}'),
          findsOneWidget,
        );
        await tester.scrollUntilVisible(
          find.text('${s.text('ロビー')}\n${code == 'ja' ? '1階' : areas[code]}'),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.scrollUntilVisible(
          find.text(code == 'ja' ? p.sourceText : explanations[code]!),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.text(s.text(code == 'ja' ? '施設の説明（原文）' : '施設が確認した説明')),
          findsOneWidget,
        );
        await tester.scrollUntilVisible(
          find.text(s.text('ルールの原文')),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text(s.text('ルールの原文')));
        await tester.pumpAndSettle();
        expect(find.text(p.sourceText), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final state in [
    'unreviewed',
    'changedRule',
    'changedTranslation',
    'missingArea',
    'futureCondition',
  ]) {
    testWidgets('$state cannot silently become translated permission', (
      tester,
    ) async {
      final json = policy(reviewed: state != 'unreviewed').toJson();
      if (state == 'changedRule') json['sourceText'] = '新しい条件';
      if (state == 'changedTranslation') {
        json['translations']['en']['text'] = 'Changed translation';
      }
      if (state == 'missingArea') json['translations']['en']['area'] = '';
      if (state == 'futureCondition') {
        json['conditions'] = ['futureRestriction'];
      }
      await tester.pumpWidget(screen(VenuePolicy.fromJson(json), 'en'));
      await tester.pumpAndSettle();
      final s = const AppStrings(Locale('en'));
      final missing = find.text(
        s.text('この言語の確認済み説明はありません。対象エリアの詳細とルールは原文・現場の案内で確認してください。'),
      );
      await tester.scrollUntilVisible(
        missing,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(missing, findsOneWidget);
      expect(find.text(explanations['en']!), findsNothing);
      expect(find.text('Changed translation'), findsNothing);
      expect(find.text(s.text('施設が確認した説明')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
