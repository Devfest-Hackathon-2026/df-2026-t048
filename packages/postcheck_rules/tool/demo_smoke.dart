// Cross-language contract test against the loopback-only Go demo server.
import 'package:postcheck_rules/postcheck_rules.dart';

Future<void> main() async {
  final org = RulesApi(
    baseUrl: 'http://127.0.0.1:8787',
    token: () async => 'postcheck-demo-org',
  );
  final operator = RulesApi(
    baseUrl: 'http://127.0.0.1:8787',
    token: () async => 'postcheck-demo-operator',
  );
  final staff = RulesApi(
    baseUrl: 'http://127.0.0.1:8787',
    token: () async => 'postcheck-demo-staff',
  );
  final visitor = RulesApi(baseUrl: 'http://127.0.0.1:8787');
  void verify(bool ok, String phase) {
    if (!ok) throw StateError(phase);
  }

  try {
    final actor = await org.session();
    verify(actor['operator'] == false, 'organization role');
    const basePolicy = VenuePolicy(
      name: '結合テスト展示館（架空）',
      applicationName: '管理画面接続の検証（架空）',
      address: '架空市1-2-3',
      contact: 'test@example.invalid',
      website: 'https://example.invalid',
      sourceUrl: 'https://example.invalid/rules',
      sourceImage:
          'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII=',
      sourceText: 'ロビーのみ写真撮影可。フラッシュと動画は禁止。試作Aは非公開。',
      areaKind: VenueArea.lobby,
      conditionCodes: ['noFlash', 'photosOnly'],
      area: 'ロビー',
      words: ['試作A'],
      photography: RulePermission.conditional,
      publication: RulePermission.conditional,
    );
    final translated = <String, RuleTranslation>{
      'en': const RuleTranslation(
        text:
            'Lobby photos only. No flash or video. Prototype A is not public.',
        area: 'Lobby',
      ),
      'zh': const RuleTranslation(text: '仅限大厅拍照。禁止闪光灯和录像。试作A不公开。', area: '大厅'),
      'ko': const RuleTranslation(
        text: '로비에서 사진만 가능합니다. 플래시·동영상은 금지이며 시제품 A는 비공개입니다.',
        area: '로비',
      ),
    };
    final policy = VenuePolicy.fromJson({
      ...basePolicy.toJson(),
      'translations': {
        for (final entry in translated.entries)
          entry.key: RuleTranslation(
            text: entry.value.text,
            area: entry.value.area,
            reviewedDigest: basePolicy.translationDigest(
              entry.key,
              entry.value,
            ),
          ).toJson(),
      },
    });
    var venue = await org.save(policy);
    verify(
      !(await visitor.list()).any((v) => v.id == venue.id),
      'draft hidden',
    );
    verify(
      (await operator.managed()).every((v) => v.id != venue.id),
      'draft hidden from operator',
    );
    try {
      await operator.save(venue.draft, existing: venue);
      throw StateError('operator edited applicant draft');
    } on RulesApiException catch (e) {
      verify(e.status == 403, 'operator edit denied');
    }
    try {
      await org.change(venue, 'submit', publicAcknowledged: true);
      throw StateError('unverified submit accepted');
    } on RulesApiException catch (e) {
      verify(e.status == 412, 'verification gate');
    }
    final request = await org.requestVerification(venue.id);
    final link = await operator.issueVerification(
      request['id'],
      'https://example.invalid/official',
    );
    verify(
      (await visitor.previewAccess(link['token']))['kind'] == 'verification',
      'anonymous preview',
    );
    await visitor.consumeAccess(link['token']);
    verify((await org.access(venue.id))['role'] == 'manager', 'bound manager');
    venue = await org.change(venue, 'submit', publicAcknowledged: true);
    venue = await operator.change(venue, 'approve');
    final published = (await visitor.list()).singleWhere(
      (v) => v.id == venue.id,
    );
    verify(
      published.policy.contact.isEmpty &&
          published.policy.sourceImage.isEmpty &&
          published.policy.words.single == '試作A',
      'public contract',
    );
    verify(published.version == venue.publishedVersion, 'version contract');
    for (final code in ['en', 'zh', 'ko']) {
      verify(
        published.policy.reviewedTranslation(code)?.text ==
            translated[code]!.text,
        'reviewed translation contract',
      );
    }
    verify(
      published.policy.conditionCodes.length == 2 &&
          published.policy.areaKind == VenueArea.lobby,
      'structured rules contract',
    );
    final invite = await org.invite(venue.id, 'editor');
    try {
      await visitor.consumeAccess(invite['token']);
      throw StateError('anonymous invitation accepted');
    } on RulesApiException catch (e) {
      verify(e.status == 403, 'invitation requires login');
    }
    await staff.consumeAccess(invite['token']);
    verify(
      (await staff.managed()).any((v) => v.id == venue.id),
      'staff scoped read',
    );
    try {
      await staff.invite(venue.id, 'manager');
      throw StateError('editor invited manager');
    } on RulesApiException catch (e) {
      verify(e.status == 403, 'editor cannot invite');
    }
    await org.revoke(venue.id, (await staff.session())['uid']);
    verify(
      (await staff.managed()).every((v) => v.id != venue.id),
      'revocation effective',
    );
    final changed = VenuePolicy.fromJson({
      ...policy.toJson(),
      'sourceText': '変更後の架空ルール。翻訳の再確認が必要。',
    });
    venue = await org.save(changed, existing: venue);
    venue = await org.change(venue, 'submit', publicAcknowledged: true);
    venue = await operator.change(venue, 'approve');
    verify(
      (await visitor.list())
          .singleWhere((v) => v.id == venue.id)
          .policy
          .translations
          .isEmpty,
      'outdated translation withheld after rules update',
    );
    await operator.change(venue, 'suspend', reason: '結合テスト終了');
    verify(!(await visitor.list()).any((v) => v.id == venue.id), 'suspension');
    print(
      'PASS: Dart → Go verification → submit → approve → multilingual public rules → invalidate translations → suspend; invite/revoke retained',
    );
  } finally {
    org.close();
    operator.close();
    visitor.close();
    staff.close();
  }
}
