import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/models.dart';
import '../domain/preferences.dart';
import '../application/preferences_codec.dart';
import 'downloaded_gemma.dart';
import '../domain/model_preparation.dart';

final class LocalSettings implements SettingsPort {
  LocalSettings(this.preferences);
  final SharedPreferences preferences;
  Map<String, dynamic> get _state {
    final raw = preferences.getString('settings.v1');
    if (raw != null) return jsonDecode(raw) as Map<String, dynamic>;
    return {
      'privateWords': preferences.getStringList('privateWords') ?? <String>[],
      'aiEnabled': preferences.getBool('aiEnabled') ?? true,
      'review': encodePreferences(const ReviewPreferences()),
    };
  }

  Future<void> _save(Map<String, dynamic> value) async {
    if (!await preferences.setString('settings.v1', jsonEncode(value))) {
      throw StateError('Settings persistence failed');
    }
  }

  @override
  List<String> get privateWords =>
      (_state['privateWords'] as List).cast<String>();
  @override
  bool get aiEnabled => _state['aiEnabled'] as bool;
  @override
  String get modelName => DownloadedGemma.name;
  @override
  ReviewPreferences get reviewPreferences =>
      decodePreferences(_state['review']);
  @override
  Future<void> saveReviewPreferences(ReviewPreferences value) =>
      _save({..._state, 'review': encodePreferences(value)});
  @override
  Future<void> replaceSettings({
    required bool aiEnabled,
    required List<String> privateWords,
    required ReviewPreferences review,
  }) async {
    await _save({
      'aiEnabled': aiEnabled,
      'privateWords': privateWords,
      'review': encodePreferences(review),
    });
    if (aiEnabled) {
      await prepareModel(resume: true);
    } else {
      await pauseModelDownload();
    }
  }

  @override
  Future<void> recordChoice(Finding finding, ReviewDecision decision) async {
    final current = reviewPreferences;
    if (!current.learningEnabled || decision == ReviewDecision.pending) {
      return;
    }
    final key = current.keyFor(finding);
    final counts = current.choices[key] ?? const ChoiceCount();
    if (counts.hide + counts.keep >= 1000000) return;
    await saveReviewPreferences(
      current.copyWith(
        choices: {...current.choices, key: counts.record(decision)},
      ),
    );
  }

  @override
  Future<String?> modelPath() async {
    return DownloadedGemma().path();
  }

  @override
  Future<ModelPreparation> modelPreparation() => DownloadedGemma().status();
  @override
  Future<ModelPreparation> prepareModel({bool resume = false}) =>
      DownloadedGemma().prepare(resume: resume);
  @override
  Future<ModelPreparation> pauseModelDownload() => DownloadedGemma().pause();

  @override
  Future<void> saveWords(String words) async {
    final values = words
        .split(RegExp(r'[\n,、]'))
        .map((w) => w.trim())
        .where((w) => w.isNotEmpty)
        .toSet()
        .toList();
    if (values.length > 500 || values.any((w) => w.length > 200)) {
      throw const FormatException('登録ワードは500件、1件200文字までです。');
    }
    await _save({..._state, 'privateWords': values});
  }

  @override
  Future<void> setAIEnabled(bool value) async {
    await _save({..._state, 'aiEnabled': value});
    if (value) {
      await prepareModel(resume: true);
    } else {
      await pauseModelDownload();
    }
  }
}

Future<void> prepareLocalPrivacy() async {
  // Clear only our own stale temporary work; never touch original library photos.
  final root = await getTemporaryDirectory();
  for (final name in ['postcheck-scan', 'postcheck-export']) {
    final directory = Directory('${root.path}/$name');
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
    await directory.create();
  }
  if (Platform.isIOS) {
    await const MethodChannel(
      'postcheck/privacy',
    ).invokeMethod<void>('excludeBackup');
  }
}
