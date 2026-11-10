import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:postcheck_rules/postcheck_rules.dart';
import 'package:postcheck_admin/access_page.dart';

Future<void> settle(WidgetTester tester) async {
  // Dialog dismissal schedules the HTTP request after an animation frame.
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'unverified owner requests verification without personal fields',
    (tester) async {
      final calls = <http.Request>[];
      final api = RulesApi(
        baseUrl: 'http://localhost',
        client: MockClient((r) async {
          calls.add(r);
          return http.Response(
            jsonEncode(
              r.method == 'GET'
                  ? {
                      'venueId': 'v',
                      'uid': 'synthetic-owner',
                      'name': '架空施設',
                      'role': 'unverified',
                      'members': [],
                    }
                  : {'id': 'request'},
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: FacilityAccessPage(api: api, venueId: 'v'),
        ),
      );
      await settle(tester);
      expect(find.byType(TextField), findsNothing);
      await tester.ensureVisible(find.text('運営に責任者確認を依頼'));
      await tester.tap(find.text('運営に責任者確認を依頼'));
      await settle(tester);
      expect(calls.where((r) => r.method == 'POST'), hasLength(1));
      expect(jsonDecode(calls.last.body), {'venueId': 'v'});
      expect(find.text('確認を依頼しました'), findsOneWidget);
    },
  );
  testWidgets('editor has no staff-management controls', (tester) async {
    final api = RulesApi(
      baseUrl: 'http://localhost',
      client: MockClient(
        (r) async => http.Response(
          jsonEncode({
            'venueId': 'v',
            'uid': 'synthetic-staff',
            'name': '架空施設',
            'role': 'editor',
            'members': [],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        home: FacilityAccessPage(api: api, venueId: 'v'),
      ),
    );
    await settle(tester);
    expect(find.text('招待リンクを発行'), findsNothing);
    expect(find.text('解除'), findsNothing);
    expect(find.text('現在の権限：担当者'), findsOneWidget);
  });
  testWidgets('operator must check official channel before issuing link', (
    tester,
  ) async {
    final calls = <http.Request>[];
    final api = RulesApi(
      baseUrl: 'http://localhost',
      client: MockClient((r) async {
        calls.add(r);
        return http.Response(
          jsonEncode(
            r.method == 'GET'
                ? [
                    {
                      'id': 'request',
                      'uid': 'synthetic-owner',
                      'name': '架空施設',
                      'status': 'requested',
                      'website': '',
                    },
                  ]
                : {'token': '0' * 64, 'expiresAt': '2026-11-10T00:00:00Z'},
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(home: VerificationRequestsPage(api: api, operator: true)),
    );
    await settle(tester);
    await tester.ensureVisible(find.text('公式窓口を確認してリンク発行'));
    await tester.tap(find.text('公式窓口を確認してリンク発行'));
    await settle(tester);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '確認リンクを発行'))
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.widgetWithText(TextField, '独立に確認した公式サイトURL'),
      'https://example.invalid',
    );
    await tester.tap(find.byType(CheckboxListTile));
    await settle(tester);
    await tester.runAsync(() async {
      await tester.tap(find.text('確認リンクを発行'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await settle(tester);
    final issued = calls.singleWhere((r) => r.method == 'POST');
    expect(issued.url.path, '/v1/access/requests/request/issue');
    expect(jsonDecode(issued.body), {
      'officialSourceUrl': 'https://example.invalid',
      'confirmed': true,
    });
    expect(find.text('公式窓口へ送る確認リンク'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
