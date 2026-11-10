# 管理Webの旧フォーム表示への対応

2026-11-09。利用者のChrome上で、削除済みの氏名・連絡先・メール欄が表示されていることを確認した。公開JSはV17の本番ビルドと一致していたが、Hostingのルート `/` とJSに `Cache-Control: max-age=3600` が付いていた。以前の完了確認は新規ブラウザと配信ファイルだけで、利用者の既存タブの表示まで確認できていなかった。

## 変更

- `/`、`/index.html`、`/main.dart.js`、`/flutter_bootstrap.js`、`/flutter.js`、`/flutter_service_worker.js`、`/maps.local.js`を `Cache-Control: no-store` にする。
- フォント等の静的アセットのキャッシュは維持する。管理APIのno-store・認証・暗号化は維持する。
- 例示設定と実際のHosting設定を同じ内容に更新し、既存Hostingへ再配置。実設定ファイルはGitに含めない。
- 施設住所の処理に残っていた、旧連絡先についての誤ったコードコメントを修正。

## 検証

配置後、ルート・main.dart.js・bootstrap・service worker・Maps初期化JS・公開APIから、それぞれHTTP `Cache-Control: no-store` が返ることを確認した。

今回の変更は配信設定とコメントだけ。`flutter test --no-pub test/editor_test.dart`を再実行し3件成功。個人欄がなく、個人連絡先を送信せず、保存・申請が動作することを確認。Chromeで強制再読み込みを実施したが、画面操作ツールの取得エラーにより再ログイン後のフォームまでは確認できていない。新しいブラウザで公開サイトの起動を確認した。既に開いている旧版タブの実行中コードは、配置だけでは置き換わらないため、一度再読み込みが必要。ブラウザに既存のHTTPキャッシュがある場合は `Command + Shift + R` を使用する。
