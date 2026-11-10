import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'multilingual_rules.dart';

// Go orders strings by UTF-8 bytes; Dart's default UTF-16 order differs for
// supplementary characters. Registered words may contain either.
/// Items a venue can switch on so that its visitors are always told about
/// them (OR with the visitor's own settings). Names match the app's
/// `CheckTarget` enum. Default: none (the venue adds nothing).
const venueCheckTargets = [
  'contact',
  'privateWord',
  'imageText',
  'face',
  'announcement',
  'context',
  'screenDevice',
  'whiteboard',
  'wineGlass',
  'book',
  'pictureFrame',
  'poster',
];

/// 施設が「必ず指摘する」項目の表示名（[venueCheckTargets]と同じ順）。
const venueCheckTargetLabels = <String, String>{
  'contact': '連絡先',
  'privateWord': '登録ワード',
  'imageText': '写り込んだ文字',
  'face': '人物',
  'announcement': '告知のタイミング',
  'context': '内容の確認（AI）',
  'screenDevice': 'パソコン・スマホ',
  'whiteboard': 'ホワイトボード',
  'wineGlass': 'お酒（ワイングラス）',
  'book': '本・資料',
  'pictureFrame': '額縁',
  'poster': 'ポスター',
};

int _compareUtf8(String a, String b) {
  final x = utf8.encode(a), y = utf8.encode(b);
  for (var i = 0; i < x.length && i < y.length; i++) {
    final difference = x[i].compareTo(y[i]);
    if (difference != 0) return difference;
  }
  return x.length.compareTo(y.length);
}

enum RulePermission {
  allowed('可'),
  forbidden('不可'),
  conditional('条件付き'),
  unknown('未確認');

  const RulePermission(this.label);
  final String label;
  static RulePermission parse(Object? value) =>
      values.firstWhere((v) => v.name == value, orElse: () => unknown);
}

final class VenuePolicy {
  const VenuePolicy({
    required this.name,
    this.applicationName = '',
    this.address = '',
    this.latitude = 35.6586,
    this.longitude = 139.7454,
    this.website = '',
    this.contact = '',
    this.event = '',
    this.area = '',
    this.areaKind = VenueArea.custom,
    this.conditionCodes = const [],
    this.sourceLanguage = 'ja',
    this.translations = const {},
    this.photography = RulePermission.unknown,
    this.publication = RulePermission.unknown,
    this.commercial = RulePermission.unknown,
    this.words = const [],
    this.checkTargets = const [],
    this.releaseAt,
    this.validUntil,
    this.sourceUrl = '',
    this.sourceImage = '',
    this.sourceText = '',
    this.visibility = 'public',
  });
  final String name,
      applicationName,
      address,
      website,
      contact,
      event,
      area,
      sourceUrl,
      sourceImage,
      sourceText,
      visibility;
  final double latitude, longitude;
  final RulePermission photography, publication, commercial;
  final VenueArea areaKind;
  final List<String> conditionCodes;
  final String sourceLanguage;
  final Map<String, RuleTranslation> translations;

  /// Length-prefixed UTF-8 fields match the Go API without JSON escaping or
  /// timestamp formatting differences. Changes invalidate previous reviews.
  String get rulesDigest {
    final codes = conditionCodes.toList()..sort();
    final sortedWords = words.toList()..sort(_compareUtf8);
    String coordinate(double value) {
      final data = ByteData(8)..setFloat64(0, value, Endian.big);
      return base64Encode(data.buffer.asUint8List());
    }

    final fields = [
      name,
      event,
      area,
      areaKind.name,
      sourceLanguage,
      sourceText,
      sourceUrl,
      photography.name,
      publication.name,
      commercial.name,
      address,
      website,
      visibility,
      coordinate(latitude),
      coordinate(longitude),
      releaseAt?.millisecondsSinceEpoch.toString() ?? '',
      validUntil?.millisecondsSinceEpoch.toString() ?? '',
      codes.length.toString(),
      ...codes,
      sortedWords.length.toString(),
      ...sortedWords,
      // Appended only when set, so venues without check items keep their
      // earlier digest (and their reviewed translations).
      if (checkTargets.isNotEmpty) ...[
        'checkTargets',
        checkTargets.length.toString(),
        ...(checkTargets.toList()..sort()),
      ],
    ];
    final canonical = fields.map((v) => '${utf8.encode(v).length}:$v').join();
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  RuleTranslation? reviewedTranslation(String languageCode) {
    final t = translations[languageCode];
    return t != null &&
            t.text.trim().isNotEmpty &&
            (area.trim().isEmpty || t.area.trim().isNotEmpty) &&
            t.reviewedDigest == translationDigest(languageCode, t)
        ? t
        : null;
  }

  String translationDigest(String languageCode, RuleTranslation translation) {
    final fields = [
      rulesDigest,
      languageCode,
      translation.text,
      translation.area,
    ];
    final canonical = fields.map((v) => '${utf8.encode(v).length}:$v').join();
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  /// Legacy detail fields remain readable, but new facilities need only check items.
  bool get hasLegacyRuleDetails =>
      photography != RulePermission.unknown ||
      publication != RulePermission.unknown ||
      commercial != RulePermission.unknown ||
      event.isNotEmpty ||
      area.isNotEmpty ||
      areaKind != VenueArea.custom ||
      conditionCodes.isNotEmpty ||
      translations.isNotEmpty ||
      words.isNotEmpty ||
      releaseAt != null ||
      validUntil != null ||
      sourceText.trim().isNotEmpty ||
      sourceUrl.isNotEmpty ||
      sourceImage.isNotEmpty;

  bool get hasUnknownConditions =>
      conditionCodes.any((code) => VenueCondition.parse(code) == null);
  final List<String> words;

  /// Subset of [venueCheckTargets] switched on by the venue staff.
  final List<String> checkTargets;
  final DateTime? releaseAt, validUntil;
  bool validAt(DateTime now) =>
      validUntil == null || now.toUtc().isBefore(validUntil!.toUtc());
  List<String> activeWords(DateTime now) =>
      validAt(now) &&
          (releaseAt == null || now.toUtc().isBefore(releaseAt!.toUtc()))
      ? words
      : const [];
  factory VenuePolicy.fromJson(Map<String, dynamic> j) => VenuePolicy(
    name: j['name'] as String,
    applicationName: j['applicationName'] ?? '',
    address: j['address'] ?? '',
    latitude: (j['latitude'] as num).toDouble(),
    longitude: (j['longitude'] as num).toDouble(),
    website: j['website'] ?? '',
    contact: j['contact'] ?? '',
    event: j['event'] ?? '',
    area: j['area'] ?? '',
    areaKind: VenueArea.parse(j['areaKind']),
    conditionCodes: List<String>.from(j['conditions'] ?? []),
    sourceLanguage: j['sourceLanguage'] ?? 'ja',
    translations: {
      for (final e
          in (j['translations'] as Map<String, dynamic>? ?? {}).entries)
        e.key: RuleTranslation.fromJson(Map<String, dynamic>.from(e.value)),
    },
    photography: RulePermission.parse(j['photography']),
    publication: RulePermission.parse(j['publication']),
    commercial: RulePermission.parse(j['commercial']),
    words: List<String>.from(j['words'] ?? []),
    checkTargets: List<String>.from(
      j['checkTargets'] ?? [],
    ).where(venueCheckTargets.contains).toSet().toList(),
    releaseAt: DateTime.tryParse(j['releaseAt'] ?? ''),
    validUntil: DateTime.tryParse(j['validUntil'] ?? ''),
    sourceUrl: () {
      final u = (j['sourceUrl'] ?? '') as String;
      return u.startsWith('data:image') ? '' : u;
    }(),
    sourceImage: () {
      final img = (j['sourceImage'] ?? '') as String;
      if (img.isNotEmpty) return img;
      final u = (j['sourceUrl'] ?? '') as String;
      return u.startsWith('data:image') ? u : '';
    }(),
    sourceText: j['sourceText'] ?? '',
    visibility: j['visibility'] ?? 'organization',
  );
  Map<String, dynamic> toJson() => {
    'name': name,
    'applicationName': applicationName,
    'address': address,
    'latitude': latitude,
    'longitude': longitude,
    'website': website,
    'event': event,
    'area': area,
    'areaKind': areaKind.name,
    'conditions': conditionCodes,
    'sourceLanguage': sourceLanguage,
    'translations': {
      for (final e in translations.entries) e.key: e.value.toJson(),
    },
    'photography': photography.name,
    'publication': publication.name,
    'commercial': commercial.name,
    'words': words,
    if (checkTargets.isNotEmpty) 'checkTargets': checkTargets,
    if (releaseAt != null) 'releaseAt': releaseAt!.toUtc().toIso8601String(),
    if (validUntil != null) 'validUntil': validUntil!.toUtc().toIso8601String(),
    'sourceUrl': sourceUrl,
    'sourceImage': sourceImage,
    'sourceText': sourceText,
    'visibility': visibility,
  };
}

final class PublishedVenue {
  const PublishedVenue({
    required this.id,
    required this.version,
    required this.policy,
    required this.updatedAt,
    this.demo = false,
  });
  final String id;
  final int version;
  final VenuePolicy policy;
  final DateTime updatedAt;
  final bool demo;
  factory PublishedVenue.fromJson(Map<String, dynamic> j) => PublishedVenue(
    id: j['id'] as String,
    version: j['version'] as int,
    policy: VenuePolicy.fromJson(j['policy']),
    updatedAt: DateTime.parse(j['updatedAt']),
  );
  String get qrValue => 'postcheck://venue/$id';
}

final class ManagedVenue {
  ManagedVenue.fromJson(Map<String, dynamic> j)
    : id = j['id'],
      org = j['org'],
      version = j['version'],
      status = j['status'],
      draft = VenuePolicy.fromJson(j['draft']),
      published = j['published'] == null
          ? null
          : VenuePolicy.fromJson(j['published']),
      publishedVersion = j['publishedVersion'],
      suspended = j['suspended'] ?? false,
      reason = j['reason'] ?? '';
  final String id, org, status, reason;
  final int version, publishedVersion;
  final VenuePolicy draft;
  final VenuePolicy? published;
  final bool suspended;
  String get statusLabel => switch (status) {
    'pending' => '審査中',
    'returned' => '差戻し',
    'published' => '公開済み',
    _ => '下書き',
  };

  /// 一覧表示用。未入力の古いデータは施設名にフォールバックする。
  String get applicationTitle {
    final t = draft.applicationName.trim();
    return t.isNotEmpty ? t : draft.name;
  }
}

abstract interface class VenueRepositoryPort {
  Future<List<PublishedVenue>> list();
}

String? venueIdFromQR(String raw) {
  final u = Uri.tryParse(raw);
  if (u == null ||
      u.scheme != 'postcheck' ||
      u.host != 'venue' ||
      u.pathSegments.length != 1 ||
      u.query.isNotEmpty ||
      u.fragment.isNotEmpty)
    return null;
  final id = u.pathSegments.single;
  return RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(id) ? id : null;
}
