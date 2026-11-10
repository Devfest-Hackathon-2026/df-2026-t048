import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:postcheck_rules/postcheck_rules.dart';
import 'package:postcheck_admin/app_theme.dart';
import 'package:postcheck_admin/venue_editor.dart';

void main() {
  testWidgets(
    'failed autosave preserves text and unsaved back requires confirmation',
    (tester) async {
      final api = RulesApi(
        baseUrl: 'http://localhost',
        client: MockClient((_) async => http.Response('', 503)),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildPostCheckTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => VenueEditor(api: api),
                  ),
                ),
                child: const Text('開く'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('開く'));
      await tester.pumpAndSettle();
      for (final key in ['contactName', 'contact', 'email']) {
        expect(find.byKey(ValueKey('venue-$key')), findsNothing);
      }
      final name = find.widgetWithText(TextFormField, '例：架空アリーナ');
      await tester.enterText(name, '架空の展示館');
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('保存せずに戻りますか？'), findsOneWidget);
      await tester.tap(find.text('編集を続ける'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        name,
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('架空の展示館'), findsOneWidget);
      expect(find.text('保存'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('戻る'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('戻る'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'check-items-only submission needs no hidden legacy inputs',
    (tester) async {
      final policy = VenuePolicy(
        name: '架空展示館',
        applicationName: '架空展示のルール申請',
        address: '〒100-0001\n架空市1-2-3',
        contact: '山田太郎 / 090-0000-0000 / demo@example.invalid',
        website: 'https://example.invalid',
        checkTargets: ['whiteboard', 'poster'],
      );
      Map<String, dynamic> json(int version, String status) => {
        'id': 'fixture',
        'org': 'demo',
        'version': version,
        'status': status,
        'draft': policy.toJson(),
        'publishedVersion': 0,
      };
      final requests = <http.Request>[];
      final api = RulesApi(
        baseUrl: 'http://localhost',
        client: MockClient((r) async {
          requests.add(r);
          return http.Response(
            jsonEncode(
              json(
                requests.length + 1,
                r.url.path.endsWith('submit') ? 'pending' : 'draft',
              ),
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildPostCheckTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => VenueEditor(
                      api: api,
                      venue: ManagedVenue.fromJson(json(1, 'draft')),
                    ),
                  ),
                ),
                child: const Text('開く'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('開く'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 2; i++) {
        final button = find.text('次へ');
        await tester.scrollUntilVisible(
          button,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button, warnIfMissed: false);
        await tester.pumpAndSettle();
      }
      await tester.scrollUntilVisible(
        find.byType(CheckboxListTile),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('申請する'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('申請する'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(requests.length, 2);
      expect(jsonDecode(requests.last.body)['publicAcknowledged'], isTrue);
      expect(
        jsonDecode(requests.first.body)['policy'].containsKey('contact'),
        isFalse,
      );
      expect(find.byType(VenueEditor), findsNothing);
      expect(find.text('開く'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'autosave serializes create and preserves edits made during request',
    (tester) async {
      final first = Completer<http.Response>();
      final requests = <http.Request>[];
      http.Response reply(http.Request r, int version) => http.Response(
        jsonEncode({
          'id': 'fixture',
          'org': 'demo',
          'version': version,
          'status': 'draft',
          'draft': jsonDecode(r.body)['policy'],
          'publishedVersion': 0,
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
      final api = RulesApi(
        baseUrl: 'http://localhost',
        client: MockClient((r) async {
          requests.add(r);
          if (requests.length == 1) return first.future;
          return reply(r, requests.length);
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildPostCheckTheme(),
          home: VenueEditor(api: api),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('venue-lat')),
        '34.6937',
      );
      await tester.enterText(
        find.byKey(const ValueKey('venue-lng')),
        '135.5023',
      );
      await tester.enterText(
        find.byKey(const ValueKey('venue-name')),
        '架空施設・変更前',
      );
      await tester.pump(const Duration(milliseconds: 900));
      expect(requests, hasLength(1));
      expect(requests.first.method, 'POST');
      await tester.enterText(
        find.byKey(const ValueKey('venue-name')),
        '架空施設・変更後',
      );
      await tester.pump(const Duration(milliseconds: 900));
      expect(requests, hasLength(1));
      await tester.runAsync(() async {
        first.complete(reply(requests.first, 1));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();
      expect(requests, hasLength(2));
      expect(requests.last.method, 'PUT');
      expect(jsonDecode(requests.last.body)['version'], 1);
      expect(jsonDecode(requests.last.body)['policy']['name'], '架空施設・変更後');
      expect(find.text('地図は未設定です。施設の正確な緯度・経度を入力してください。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
