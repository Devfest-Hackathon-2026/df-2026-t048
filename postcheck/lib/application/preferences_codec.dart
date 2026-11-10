import 'dart:convert';
import '../domain/models.dart';
import '../domain/preferences.dart';

Map<String, Object?> encodePreferences(ReviewPreferences value) => {
  'disabledTargets': value.disabledTargets.map((e) => e.name).toList(),
  'learningEnabled': value.learningEnabled,
  'choices': value.choices.map(
    (key, value) => MapEntry(key, {'hide': value.hide, 'keep': value.keep}),
  ),
};

/// Also reads settings saved before 2026-11-10, which had a personal /
/// enterprise `mode` and `requiredKinds`. Those fields are ignored and choice
/// counts learned in the removed enterprise mode are dropped.
ReviewPreferences decodePreferences(Object? value) {
  if (value is! Map) throw const FormatException('設定の形式が不正です。');
  final disabled = <CheckTarget>{};
  final rawDisabled = value['disabledTargets'];
  if (rawDisabled != null) {
    if (rawDisabled is! List) throw const FormatException('設定の形式が不正です。');
    for (final name in rawDisabled) {
      final match = CheckTarget.values.where((e) => e.name == name);
      if (match.isEmpty) throw const FormatException('不明な検出項目です。');
      disabled.add(match.first);
    }
  }
  final choices = <String, ChoiceCount>{};
  final entries = value['choices'] as Map;
  if (entries.length > 100) throw const FormatException('学習データが多すぎます。');
  final validKeys = <String>{
    for (final m in ['personal', 'enterprise'])
      for (final k in FindingKind.values)
        for (final t in ['caption', 'photo', 'whole']) '$m:${k.name}:$t',
  };
  for (final entry in entries.entries) {
    if (!validKeys.contains(entry.key)) {
      throw const FormatException('不明な学習項目です。');
    }
    final h = entry.value['hide'], k = entry.value['keep'];
    if (h is! int || k is! int || h < 0 || k < 0 || h + k > 1000000) {
      throw const FormatException('学習データの形式が不正です。');
    }
    if ((entry.key as String).startsWith('enterprise:')) continue;
    choices[entry.key as String] = ChoiceCount(hide: h, keep: k);
  }
  return ReviewPreferences(
    disabledTargets: disabled,
    learningEnabled: value['learningEnabled'] as bool,
    choices: choices,
  );
}

/// Explicit allow-list: never serialize drafts, findings, OCR or model paths.
String encodeBackup(SettingsPort settings, {bool includeWords = true}) =>
    jsonEncode({
      'schema': 1,
      'aiEnabled': settings.aiEnabled,
      'privateWords': includeWords ? settings.privateWords : <String>[],
      'review': encodePreferences(settings.reviewPreferences),
    });

final class RestoredSettings {
  const RestoredSettings(this.aiEnabled, this.words, this.review);
  final bool aiEnabled;
  final List<String> words;
  final ReviewPreferences review;
}

RestoredSettings decodeBackup(String payload) {
  if (payload.length > 131072) throw const FormatException('バックアップが大きすぎます。');
  try {
    final map = jsonDecode(payload) as Map;
    if (map['schema'] != 1) throw const FormatException('未対応のバックアップです。');
    final words = (map['privateWords'] as List).cast<String>();
    if (words.length > 500 ||
        words.any((w) => w.length > 200 || w.trim().isEmpty)) {
      throw const FormatException('登録ワードが上限を超えています。');
    }
    return RestoredSettings(
      map['aiEnabled'] as bool,
      words,
      decodePreferences(map['review']),
    );
  } catch (_) {
    throw const FormatException('バックアップの形式を確認できません。');
  }
}
