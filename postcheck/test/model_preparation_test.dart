import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:postcheck/adapters/downloaded_gemma.dart';
import 'package:postcheck/adapters/local_gemma.dart';
import 'package:postcheck/adapters/local_storage.dart';
import 'package:postcheck/domain/models.dart';
import 'package:postcheck/domain/model_preparation.dart';
import 'package:postcheck/presentation/settings_page.dart';
import 'package:postcheck/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(
    () => messenger.setMockMethodCallHandler(DownloadedGemma.channel, null),
  );

  test(
    'model operations never pass a draft, URL or other payload to native code',
    () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(DownloadedGemma.channel, (call) async {
        calls.add(call.method);
        expect(call.arguments, isNull);
        return {'phase': 'waiting', 'received': 0};
      });
      final model = DownloadedGemma();
      await model.prepare();
      await model.prepare(resume: true);
      await model.pause();
      expect(calls, ['start', 'retry', 'pause']);
    },
  );

  test(
    'pending download preserves basic checks without waiting for the model',
    () async {
      messenger.setMockMethodCallHandler(DownloadedGemma.channel, (call) async {
        if (call.method == 'path') return null;
        return {'phase': 'downloading', 'received': 1000};
      });
      final settings = LocalSettings(await SharedPreferences.getInstance());
      final result = await ConfiguredGemmaAdapter(
        settings,
      ).analyze(const DraftInput(caption: '架空の投稿'), const Observations());
      expect(result.findings, isEmpty);
      expect(result.status, 'AIの準備が完了していないため、文字・顔・ルールで確認しました。');
      expect(
        (await settings.modelPreparation()).phase,
        ModelPreparationPhase.downloading,
      );
    },
  );

  test(
    'disabled AI persists, stops retrieval, and does not look up a model on check',
    () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(DownloadedGemma.channel, (call) async {
        calls.add(call.method);
        return {'phase': 'paused'};
      });
      final prefs = await SharedPreferences.getInstance();
      await LocalSettings(prefs).setAIEnabled(false);
      final settings = LocalSettings(prefs);
      await ConfiguredGemmaAdapter(
        settings,
      ).analyze(const DraftInput(caption: '架空'), const Observations());
      expect(calls, ['pause']);
      expect(settings.aiEnabled, isFalse);
    },
  );

  test(
    'only a complete file returned by the native verifier can be opened',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'postcheck-model-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/verified.litertlm');
      final handle = await file.open(mode: FileMode.write);
      await handle.truncate(DownloadedGemma.size);
      await handle.close();
      messenger.setMockMethodCallHandler(
        DownloadedGemma.channel,
        (_) async => file.path,
      );
      expect(await DownloadedGemma().path(), file.path);
      await file.writeAsBytes([1]);
      expect(await DownloadedGemma().path(), isNull);
    },
  );

  test(
    'unavailable bridge and unknown state never claim AI is ready',
    () async {
      messenger.setMockMethodCallHandler(
        DownloadedGemma.channel,
        (_) async => {'phase': 'future-state'},
      );
      expect(
        (await DownloadedGemma().status()).phase,
        ModelPreparationPhase.unavailable,
      );
      messenger.setMockMethodCallHandler(
        DownloadedGemma.channel,
        (_) async => throw PlatformException(code: 'unavailable'),
      );
      expect(
        (await DownloadedGemma().status()).phase,
        ModelPreparationPhase.unavailable,
      );
      expect(await DownloadedGemma().path(), isNull);
    },
  );

  test('English download progress is localized', () {
    expect(
      const AppStrings(
        Locale('en'),
      ).text('モデル取得 50.0% · 取得済み 1294.1 MB / 2588.1 MB'),
      'Model download 50.0% · Downloaded 1294.1 MB / 2588.1 MB',
    );
  });

  testWidgets(
    'download progress, stop, retry, ready state and AI OFF are usable',
    (tester) async {
      var phase = 'downloading';
      var received = DownloadedGemma.size ~/ 2;
      messenger.setMockMethodCallHandler(DownloadedGemma.channel, (call) async {
        if (call.method == 'pause') phase = 'paused';
        if (call.method == 'retry') {
          phase = 'verifying';
          received = DownloadedGemma.size;
        }
        return {'phase': phase, 'received': received};
      });
      final settings = LocalSettings(await SharedPreferences.getInstance());
      await tester.pumpWidget(
        MaterialApp(home: SettingsPage(settings: settings)),
      );
      await tester.pump();
      expect(
        find.text('モデル取得 50.0% · 取得済み 1294.1 MB / 2588.1 MB'),
        findsOneWidget,
      );
      await tester.tap(find.text('端末内AI'));
      await tester.pump();
      expect(find.text('モデル取得 50.0%'), findsOneWidget);
      expect(find.text('取得済み 1294.1 MB / 2588.1 MB'), findsOneWidget);
      received = DownloadedGemma.size - 1;
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.text('モデル取得 99.9%'), findsOneWidget);
      expect(find.text('ファイルから追加'), findsNothing);
      expect(find.text('Gemma 4 E2B（アプリ内蔵）'), findsNothing);
      await tester.tap(find.text('取得を止める'));
      await tester.pumpAndSettle();
      expect(find.text('取得を再開'), findsOneWidget);
      expect(find.text('モデル取得 99.9%'), findsOneWidget);
      await tester.tap(find.text('取得を再開'));
      await tester.pump();
      await tester.pump();
      expect(find.text('モデル取得 100.0%'), findsOneWidget);
      expect(find.text('取得したモデルを確認しています。'), findsOneWidget);
      expect(find.text('準備できました。端末内でAI補助を使えます。'), findsNothing);
      phase = 'ready';
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.text('準備できました。端末内でAI補助を使えます。'), findsOneWidget);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(settings.aiEnabled, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
