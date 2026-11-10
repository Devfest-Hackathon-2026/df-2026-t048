import 'dart:io';
import 'package:flutter/services.dart';
import 'package:litertlm/litertlm.dart' as lm;
import 'package:path_provider/path_provider.dart';
import 'package:postcheck_rules/contracts.dart';
import '../application/ai_contract.dart';
import '../application/analysis_gate.dart';
import '../domain/models.dart';
import '../domain/ports.dart';
import '../domain/preferences.dart';

final class ConfiguredGemmaAdapter implements ContextAnalysisPort {
  ConfiguredGemmaAdapter(this.settings, {this.languageCode});
  final String Function()? languageCode;
  final SettingsPort settings;
  bool _running = false;
  @override
  Future<ContextResult> analyze(
    DraftInput draft,
    Observations observations, {
    PublishedVenue? venue,
  }) async {
    if (_running) {
      return const ContextResult(status: '前のAI処理が終了するまで、基本チェックを表示します。');
    }
    _running = true;
    try {
      return await LocalGemmaAdapter(
        modelPath: settings.aiEnabled ? await settings.modelPath() : null,
        enabled: settings.aiEnabled,
        responseLanguage: languageCode?.call() ?? 'ja',
      ).analyze(draft, observations, venue: venue);
    } finally {
      _running = false;
    }
  }
}

/// No HTTP client and no cloud fallback. The file must already be on this device.
final class LocalGemmaAdapter implements ContextAnalysisPort {
  LocalGemmaAdapter({
    required this.modelPath,
    this.enabled = true,
    this.responseLanguage = 'ja',
    this.tuned = const bool.fromEnvironment(
      'POSTCHECK_CONTEXT_V2',
      defaultValue: true,
    ),
  });
  final String responseLanguage;
  final String? modelPath;
  final bool enabled, tuned;

  @override
  Future<ContextResult> analyze(
    DraftInput draft,
    Observations observations, {
    PublishedVenue? venue,
  }) async {
    if (!enabled) {
      return const ContextResult(status: 'AI補助はオフです。文字・顔・ルールで確認しました。');
    }
    if (modelPath == null || !await File(modelPath!).exists()) {
      return const ContextResult(status: 'AIの準備が完了していないため、文字・顔・ルールで確認しました。');
    }
    final gate = AnalysisGate.shared;
    if (!gate.acquire()) {
      return const ContextResult(status: '前の端末内処理が終了するまで、基本チェックを表示します。');
    }
    final input = buildContextInput(draft, observations, venue: venue);
    lm.Engine? engine;
    lm.Conversation? conversation;
    try {
      if (Platform.isIOS) {
        await const MethodChannel(
          'postcheck/privacy',
        ).invokeMethod<void>('keepAwake', true);
      }
      lm.setMinimumLogLevel(lm.LogSeverity.error);
      final directory = await getApplicationCacheDirectory();
      engine = lm.Engine(
        engineConfig: lm.EngineConfig(
          modelPath: modelPath!,
          backend: const lm.Backend.gpu(),
          visionBackend: const lm.Backend.cpu(),
          maxNumTokens: 4096,
          cacheDir: directory.path,
        ),
      );
      await engine.initialize();
      conversation = await engine.createConversation(
        lm.ConversationConfig(
          systemMessage: lm.Message.system(
            contextSystemPromptFor(
              responseLanguage,
              tuned: tuned,
              venueRules: input.venueRule != null,
            ),
          ),
          sessionConfig: const lm.SessionConfig(
            samplerConfig: lm.SamplerConfig(topK: 1, topP: .9, temperature: .1),
          ),
          automaticToolCalling: false,
        ),
      );
      final response = await conversation.sendMessage(
        lm.Message.userContents(
          lm.Contents([
            if (draft.photo != null) lm.Content.imageBytes(draft.photo!.bytes),
            lm.Content.text(input.prompt),
          ]),
        ),
        maxOutputTokens: 1200,
      );
      return ContextResult(
        findings: parseContextFindings(
          response.text,
          input.draft,
          input.observations,
          originalDraft: draft,
          venueRule: input.venueRule,
        ),
        status: 'Gemmaが端末内で文章・画像の確認を補助しました。',
        venueReviewCompleted: input.venueRule != null,
      );
    } on FormatException {
      return const ContextResult(
        status: 'AIの回答を読み取れませんでした。文字・顔・ルールの結果を表示しています。',
      );
    } catch (_) {
      // SDK errors may embed inspected text, so do not log or surface raw errors.
      return const ContextResult(
        status: '端末内AIを実行できませんでした。対応モデル・端末の空きメモリを確認してください。',
      );
    } finally {
      if (Platform.isIOS) {
        try {
          await const MethodChannel(
            'postcheck/privacy',
          ).invokeMethod<void>('keepAwake', false);
        } catch (_) {
          /* The OS also resets this when the process exits. */
        }
      }
      try {
        await conversation?.dispose();
      } catch (_) {
        /* Best-effort native cleanup. */
      }
      try {
        await engine?.dispose();
      } catch (_) {
        /* Best-effort native cleanup. */
      }
      gate.release();
    }
  }
}
