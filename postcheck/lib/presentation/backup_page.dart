import '../l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import '../domain/cloud_backup.dart';
import '../domain/preferences.dart';
import '../application/preferences_codec.dart';
import '../application/restore_settings.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key, required this.cloud, required this.settings});
  final CloudBackupPort cloud;
  final SettingsPort settings;
  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _working = false, _loaded = false;
  String _status = '';
  CloudSnapshot? _remote;
  Future<void> _run(Future<void> Function() action) async {
    if (_working) return;
    setState(() {
      _working = true;
      _status = '';
    });
    try {
      await action();
    } on FormatException catch (e) {
      if (mounted) _status = e.message;
    } catch (_) {
      if (mounted) _status = '処理を完了できませんでした。接続・ログイン状態を確認してください。';
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _fetch() async {
    _loaded = false;
    final value = await widget.cloud.fetch();
    _remote = value;
    _loaded = true;
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: AppText(title),
          content: AppText(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const AppText('戻る'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const AppText('実行する'),
            ),
          ],
        ),
      ) ??
      false;
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_working,
    child: Scaffold(
      appBar: AppBar(title: const AppText('クラウド保存・復元')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.cloud_sync_outlined, size: 54),
          const SizedBox(height: 16),
          const AppText(
            '端末を変えても、自分の設定を。',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          const AppText(
            '設定・指摘する項目・登録ワード・学習した選択回数を保存します。写真・投稿文・OCR結果・編集履歴・AIモデルは送りません。',
          ),
          const SizedBox(height: 12),
          const AppText(
            '通信はHTTPS、保存する設定はサーバーで暗号化し、鍵はCloud KMSで管理します。本人確認済みの復元処理で復号します。運営にも読めないE2E暗号化ではありません。',
          ),
          const SizedBox(height: 12),
          if (!widget.cloud.configured)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: AppText(
                  'クラウドは未接続です。今回は接続コードまでの試作です。配置・認証設定後に利用できます。写真のチェックや端末内の設定はそのまま使えます。',
                ),
              ),
            ),
          if (!widget.cloud.signedIn) ...[
            FilledButton.icon(
              onPressed: !widget.cloud.configured || _working
                  ? null
                  : () => _run(() async {
                      await widget.cloud.signIn(LoginProvider.google);
                      await _fetch();
                    }),
              icon: const Icon(Icons.login),
              label: const AppText('Googleでログイン'),
            ),
            OutlinedButton.icon(
              onPressed: !widget.cloud.configured || _working
                  ? null
                  : () => _run(() async {
                      await widget.cloud.signIn(LoginProvider.apple);
                      await _fetch();
                    }),
              icon: const Icon(Icons.apple),
              label: const AppText('Appleでログイン'),
            ),
            const AppText('復元時は、保存したときと同じログイン方法・アカウントを選んでください。'),
          ] else ...[
            const AppText('ログイン済み。保存・復元はボタンを押したときだけ実行します。'),
            TextButton(
              onPressed: _working ? null : () => _run(_fetch),
              child: const AppText('クラウドの状態を再取得'),
            ),
            if (_loaded)
              AppText(
                _remote == null
                    ? 'まだクラウドに保存されていません。'
                    : '最終保存：${_remote!.updatedAt.toLocal()}',
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _working || !_loaded
                  ? null
                  : () => _run(() async {
                      if (!await _confirm(
                        'この端末の設定を保存しますか？',
                        '登録ワードも送信して暗号化保存します。既存のクラウド設定がある場合は置き換わります。',
                      )) {
                        return;
                      }
                      await widget.cloud.save(
                        encodeBackup(widget.settings),
                        expectedRevision: _remote?.revision,
                      );
                      await _fetch();
                      _status = 'クラウドに保存しました。';
                    }),
              child: const AppText('この端末の設定を保存'),
            ),
            OutlinedButton(
              onPressed: _working || !_loaded || _remote == null
                  ? null
                  : () => _run(() async {
                      final snapshot = _remote!;
                      final data = decodeBackup(snapshot.payload);
                      if (!await _confirm(
                        'クラウドの設定で復元しますか？',
                        'この端末の設定を置き換えます。登録ワード ${data.words.length}件、学習傾向 ${data.review.choices.length}種類。端末内の写真・下書き・モデルは復元対象外です。',
                      )) {
                        return;
                      }
                      await RestoreSettings(widget.settings)(snapshot.payload);
                      _status = '設定を復元しました。下書きは再チェックしてください。';
                    }),
              child: const AppText('この端末に復元'),
            ),
            TextButton(
              onPressed: _working || !_loaded || _remote == null
                  ? null
                  : () => _run(() async {
                      if (!await _confirm(
                        'クラウドの保存データを削除しますか？',
                        'このアカウントのバックアップを削除します。端末内の設定は残ります。',
                      )) {
                        return;
                      }
                      await widget.cloud.delete(_remote!.revision);
                      await _fetch();
                      _status = 'クラウドの保存データを削除しました。';
                    }),
              child: const AppText('クラウドの保存データを削除'),
            ),
            TextButton(
              onPressed: _working
                  ? null
                  : () => _run(() async {
                      await widget.cloud.signOut();
                      _remote = null;
                      _loaded = false;
                    }),
              child: const AppText('ログアウト'),
            ),
          ],
          if (_working) const LinearProgressIndicator(),
          if (_status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: AppText(_status),
            ),
        ],
      ),
    ),
  );
}
