import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:postcheck_rules/postcheck_rules.dart';
import 'package:postcheck_admin/app_theme.dart';
import 'package:postcheck_admin/venue_detail.dart';
import 'package:postcheck_admin/venue_editor.dart';

const _base = VenuePolicy(
  name: '架空施設',
  applicationName: '架空申請',
  address: '〒100-0001\n架空市',
  sourceText: 'ロビー撮影可',
  photography: RulePermission.allowed,
  publication: RulePermission.allowed,
  commercial: RulePermission.forbidden,
);

Map<String, dynamic> _record(VenuePolicy p, int version, String status) => {
  'id': 'fiction',
  'org': 'fiction',
  'version': version,
  'status': status,
  'draft': p.toJson(),
  'publishedVersion': 0,
};

void main() {
  test('labels cover every allowed check target', () {
    expect(venueCheckTargetLabels.keys.toList(), venueCheckTargets);
    expect(checkTargetsLabel(const []), 'なし');
    expect(checkTargetsLabel(const ['poster', 'face']), '人物、ポスター');
  });

  testWidgets('check targets load, toggle and survive autosave', (
    tester,
  ) async {
    final saved = <VenuePolicy>[];
    final api = RulesApi(
      baseUrl: 'http://localhost',
      client: MockClient((r) async {
        final p = VenuePolicy.fromJson(jsonDecode(r.body)['policy']);
        saved.add(p);
        return http.Response(
          jsonEncode(_record(p, saved.length + 1, 'draft')),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        home: VenueEditor(
          api: api,
          venue: ManagedVenue.fromJson(
            _record(
              const VenuePolicy(
                name: '架空施設',
                applicationName: '架空申請',
                address: '〒100-0001\n架空市',
                sourceText: 'ロビー撮影可',
                photography: RulePermission.allowed,
                publication: RulePermission.allowed,
                commercial: RulePermission.forbidden,
                checkTargets: ['poster'],
              ),
              1,
              'draft',
            ),
          ),
        ),
      ),
    );
    Future<void> show(Finder f) async {
      await tester.scrollUntilVisible(
        f,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
    }

    Future<void> autosave() async {
      await tester.pump(const Duration(milliseconds: 900));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
    }

    await show(find.text('次へ'));
    await tester.tap(find.text('次へ'));
    await tester.pumpAndSettle();
    expect(find.text('この施設で必ず指摘する項目'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(
      find.byType(CheckboxListTile),
      findsNWidgets(venueCheckTargets.length),
    );
    for (final label in [
      'イベント名',
      '撮影許可',
      '公開範囲',
      '商用利用',
      '具体的な条件',
      '根拠',
      '参考URL',
      '言語別の説明と対象エリア',
      '配信範囲',
    ]) {
      expect(find.text(label), findsNothing);
    }
    for (final target in venueCheckTargets) {
      final tile = tester.widget<CheckboxListTile>(
        find.byKey(ValueKey('checkTarget-$target')),
      );
      expect(tile.value, target == 'poster', reason: target);
    }
    final face = find.byKey(const ValueKey('checkTarget-face'));
    await show(face);
    await tester.tap(face);
    await tester.pumpAndSettle();
    await autosave();
    expect(saved.last.checkTargets, ['face', 'poster']);

    final poster = find.byKey(const ValueKey('checkTarget-poster'));
    await show(poster);
    await tester.tap(poster);
    await tester.pumpAndSettle();
    await autosave();
    expect(saved.last.checkTargets, ['face']);

    await show(face);
    await tester.tap(face);
    await tester.pumpAndSettle();
    await autosave();
    expect(saved.last.checkTargets, isEmpty);
    expect(saved.last.toJson().containsKey('checkTargets'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('operator review shows check targets before approval', (
    tester,
  ) async {
    final api = RulesApi(
      baseUrl: 'http://localhost',
      client: MockClient((_) async => http.Response('', 503)),
    );
    addTearDown(api.close);
    final policy = VenuePolicy.fromJson({
      ..._base.toJson(),
      'checkTargets': ['whiteboard', 'face'],
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPostCheckTheme(),
        home: VenueDetail(
          api: api,
          venue: ManagedVenue.fromJson(_record(policy, 2, 'pending')),
          operator: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('この施設で必ず指摘する項目'), findsOneWidget);
    expect(find.text('人物、ホワイトボード'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('applicant detail and policy card show なし when empty', (
    tester,
  ) async {
    final api = RulesApi(
      baseUrl: 'http://localhost',
      client: MockClient((_) async => http.Response('', 503)),
    );
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPostCheckTheme(),
        home: VenueDetail(
          api: api,
          venue: ManagedVenue.fromJson(_record(_base, 2, 'pending')),
          operator: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('この施設で必ず指摘する項目'), findsOneWidget);
    expect(find.text('なし'), findsWidgets);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PolicyCard(
              policy: VenuePolicy.fromJson({
                ..._base.toJson(),
                'checkTargets': ['poster', 'unknown'],
              }),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('必ず指摘する項目'), findsOneWidget);
    expect(find.text('ポスター'), findsOneWidget);
  });
}
