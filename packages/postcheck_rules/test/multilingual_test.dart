import 'dart:convert';
import 'dart:io';
import 'package:postcheck_rules/postcheck_rules.dart';
import 'package:test/test.dart';

void main() {
  final vector =
      jsonDecode(File('testdata/multilingual_policy.json').readAsStringSync())
          as Map<String, dynamic>;
  Map<String, dynamic> source() => jsonDecode(jsonEncode(vector['policy']));
  test('checkTargets change the digest only when set (shared with Go)', () {
    final base = VenuePolicy.fromJson(source());
    expect(base.checkTargets, isEmpty);
    expect(base.rulesDigest, vector['rulesDigest']);
    final withTargets = VenuePolicy.fromJson(
      source()..['checkTargets'] = ['whiteboard', 'face', 'contact', 'bogus'],
    );
    expect(withTargets.checkTargets, ['whiteboard', 'face', 'contact']);
    // Same value as TestCheckTargetsDigestContract in cloud/internal/rules.
    expect(
      withTargets.rulesDigest,
      'db398a5f59da57f66ddc3fb3c818236de1e0d0151ab0ed86e5277a53d3f5ad78',
    );
    expect(withTargets.toJson()['checkTargets'], [
      'whiteboard',
      'face',
      'contact',
    ]);
    expect(base.toJson().containsKey('checkTargets'), isFalse);
  });
  test('Dart/Go review tokens agree for Unicode, URLs and UTC timestamps', () {
    final p = VenuePolicy.fromJson(source());
    expect(p.rulesDigest, vector['rulesDigest']);
    expect(
      p.translationDigest('en', p.translations['en']!),
      vector['translationDigest'],
    );
    expect(p.reviewedTranslation('en')?.area, 'East side, first floor');
    expect(
      VenuePolicy.fromJson(p.toJson()).reviewedTranslation('en')?.text,
      p.translations['en']!.text,
    );
  });
  test(
    'all changes in meaning and translated wording require review again',
    () {
      final changes = <String, dynamic>{
        'sourceText': '撮影不可',
        'address': '別の住所',
        'website': 'https://example.invalid/newsite',
        'latitude': 36.0,
        'longitude': 140.0,
        'words': ['別のワード'],
        'visibility': 'organization',
        'area': '2階',
        'areaKind': 'exhibitionRooms',
        'photography': 'forbidden',
        'publication': 'unknown',
        'commercial': 'allowed',
        'sourceLanguage': 'ko',
        'name': '別施設',
        'event': '別イベント',
        'sourceUrl': 'https://example.invalid/new',
        'conditions': ['noTripod'],
        'releaseAt': '2026-11-20T00:00:00Z',
        'validUntil': '2026-12-02T00:00:00Z',
      };
      for (final change in changes.entries) {
        expect(
          VenuePolicy.fromJson(
            source()..[change.key] = change.value,
          ).reviewedTranslation('en'),
          isNull,
          reason: change.key,
        );
      }
      for (final field in ['text', 'area']) {
        final json = source();
        json['translations']['en'][field] = 'Changed';
        expect(VenuePolicy.fromJson(json).reviewedTranslation('en'), isNull);
      }
      final relabeled = source();
      relabeled['translations']['ko'] = relabeled['translations']['en'];
      expect(VenuePolicy.fromJson(relabeled).reviewedTranslation('ko'), isNull);
      final reordered = source();
      reordered['conditions'] = ['creditRequired', 'noFlash', 'photosOnly'];
      expect(
        VenuePolicy.fromJson(reordered).reviewedTranslation('en'),
        isNotNull,
      );
    },
  );
  test(
    'legacy rules retain original area and unknown future conditions are visible',
    () {
      final json = source()
        ..remove('sourceLanguage')
        ..remove('areaKind')
        ..remove('translations');
      json['conditions'] = ['futureRestriction'];
      final p = VenuePolicy.fromJson(json);
      expect(p.sourceLanguage, 'ja');
      expect(p.areaKind, VenueArea.custom);
      expect(p.area, '1階・東側');
      expect(p.hasUnknownConditions, isTrue);
      expect(p.toJson()['conditions'], ['futureRestriction']);
      expect(p.reviewedTranslation('en'), isNull);
    },
  );
}
