/// Fixed wording is translated by the app; facility-authored text stays literal.
enum VenueCondition {
  noFlash('フラッシュ禁止', 'photography'),
  noTripod('三脚禁止', 'photography'),
  photosOnly('写真のみ・動画撮影不可', 'photography'),
  designatedAreasOnly('指定エリアのみ撮影可', 'photography'),
  noLiveStreaming('ライブ配信不可', 'publication'),
  creditRequired('公開時にクレジット表記が必要', 'publication'),
  subjectsConsentRequired('写っている方の掲載許可が必要', 'publication'),
  personalUseOnly('個人利用のみ', 'commercial');

  const VenueCondition(this.label, this.aspect);
  final String label, aspect;
  static VenueCondition? parse(String code) =>
      values.where((v) => v.name == code).firstOrNull;
}

enum VenueArea {
  custom('施設が指定したエリア'),
  entireVenue('施設全体'),
  lobby('ロビー'),
  exhibitionRooms('展示室'),
  outdoors('屋外'),
  designatedOnly('指定エリア');

  const VenueArea(this.label);
  final String label;
  static VenueArea parse(Object? code) =>
      values.where((v) => v.name == code).firstOrNull ?? custom;
}

const ruleLanguages = {
  'ja': '日本語',
  'en': 'English',
  'zh': '中文（简体）',
  'ko': '한국어',
};

final class RuleTranslation {
  const RuleTranslation({
    required this.text,
    this.area = '',
    this.reviewedDigest = '',
  });
  final String text, area, reviewedDigest;
  factory RuleTranslation.fromJson(Map<String, dynamic> j) => RuleTranslation(
    text: j['text'] ?? '',
    area: j['area'] ?? '',
    reviewedDigest: j['reviewedDigest'] ?? '',
  );
  Map<String, dynamic> toJson() => {
    'text': text,
    'area': area,
    'reviewedDigest': reviewedDigest,
  };
}
