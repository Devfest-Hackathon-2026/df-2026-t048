import 'contracts.dart';
import 'multilingual_rules.dart';

final class DemoVenueRepository implements VenueRepositoryPort {
  const DemoVenueRepository();
  @override
  Future<List<PublishedVenue>> list() async => [
    PublishedVenue(
      id: 'demo-exhibition',
      version: 1,
      demo: true,
      updatedAt: DateTime.utc(2026, 11, 8),
      policy: _withReviewedDemoTranslations(
        VenuePolicy(
          name: 'みなと展示館（架空）',
          event: '秋のものづくり展',
          address: '架空の展示会場',
          areaKind: VenueArea.lobby,
          conditionCodes: const ['noFlash', 'photosOnly'],
          photography: RulePermission.conditional,
          publication: RulePermission.conditional,
          commercial: RulePermission.unknown,
          words: const ['試作A'],
          releaseAt: DateTime.utc(2026, 11, 19, 15),
          sourceText:
              'ロビーのみ写真撮影可。フラッシュ・動画は禁止。展示札「試作A」を写真に写す場合は、11月20日 00:00（日本時間）まで名前を隠してください。架空データです。',
          sourceUrl: 'https://minato.example.org/rules',
        ),
        const {
          'en': RuleTranslation(
            text:
                'Photos only in the lobby. No flash or video. Hide the name “試作A” on exhibit labels until November 20, 00:00 Japan time. All information is fictional.',
          ),
          'zh': RuleTranslation(
            text:
                '仅限大厅拍照。禁止闪光灯和录像。照片中展牌上的名称“試作A”须遮盖至11月20日00:00（日本时间）。所有信息均为虚构。',
          ),
          'ko': RuleTranslation(
            text:
                '로비에서 사진만 가능합니다. 플래시·동영상은 금지입니다. 전시 표지의 이름 ‘試作A’는 11월 20일 00:00(일본 시간)까지 가려 주세요. 모두 가상 정보입니다.',
          ),
        },
      ),
    ),
    PublishedVenue(
      id: 'demo-hall',
      version: 1,
      demo: true,
      updatedAt: DateTime.utc(2026, 11, 8),
      policy: const VenuePolicy(
        name: 'みなとホール（架空）',
        latitude: 35.662,
        longitude: 139.750,
        area: 'ホール内',
        photography: RulePermission.forbidden,
        publication: RulePermission.unknown,
        sourceText: 'ホール内は撮影できません。架空データです。',
      ),
    ),
  ];
}

// Fictional reviewed content for the local demo; never a real venue approval.
VenuePolicy _withReviewedDemoTranslations(
  VenuePolicy p,
  Map<String, RuleTranslation> translations,
) => VenuePolicy.fromJson({
  ...p.toJson(),
  'translations': {
    for (final entry in translations.entries)
      entry.key: RuleTranslation(
        text: entry.value.text,
        area: entry.value.area,
        reviewedDigest: p.translationDigest(entry.key, entry.value),
      ).toJson(),
  },
});
