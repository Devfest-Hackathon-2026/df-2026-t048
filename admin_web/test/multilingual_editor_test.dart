import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:postcheck_rules/postcheck_rules.dart';
import 'package:postcheck_admin/venue_editor.dart';

void main() {
  testWidgets(
    'check item edits preserve existing legacy rules and translations',
    (tester) async {
      const base = VenuePolicy(
        name: '架空施設',
        applicationName: '架空申請',
        address: '〒100-0001\n架空市',
        area: '1階',
        sourceText: 'ロビー撮影可',
        photography: RulePermission.allowed,
        publication: RulePermission.allowed,
        commercial: RulePermission.forbidden,
      );
      final legacy = VenuePolicy.fromJson({
        ...base.toJson(),
        'translations': {
          'en': const RuleTranslation(
            text: 'Lobby photos only.',
            area: 'First floor',
            reviewedDigest:
                '0000000000000000000000000000000000000000000000000000000000000000',
          ).toJson(),
        },
      });
      Map<String, dynamic> record(VenuePolicy p, int version) => {
        'id': 'fiction',
        'org': 'fiction',
        'version': version,
        'status': 'draft',
        'draft': p.toJson(),
        'publishedVersion': 0,
      };
      final saved = <VenuePolicy>[];
      final api = RulesApi(
        baseUrl: 'http://localhost',
        client: MockClient((r) async {
          final p = VenuePolicy.fromJson(jsonDecode(r.body)['policy']);
          saved.add(p);
          return http.Response(
            jsonEncode(record(p, saved.length + 1)),
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
            venue: ManagedVenue.fromJson(record(legacy, 1)),
          ),
        ),
      );
      Future<void> show(Finder f, {double delta = 250}) async {
        await tester.scrollUntilVisible(
          f,
          delta,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(f);
        await tester.pumpAndSettle();
      }

      await show(find.text('次へ'));
      await tester.tap(find.text('次へ'));
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNothing);
      expect(
        find.byType(DropdownButtonFormField<RulePermission>),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('translation-en')), findsNothing);
      final face = find.byKey(const ValueKey('checkTarget-face'));
      await show(face);
      await tester.tap(face);
      await tester.pump(const Duration(milliseconds: 900));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      expect(saved.last.checkTargets, ['face']);
      expect(saved.last.sourceText, legacy.sourceText);
      expect(saved.last.area, legacy.area);
      expect(saved.last.photography, legacy.photography);
      expect(saved.last.publication, legacy.publication);
      expect(saved.last.commercial, legacy.commercial);
      expect(
        saved.last.translations['en']!.toJson(),
        legacy.translations['en']!.toJson(),
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
