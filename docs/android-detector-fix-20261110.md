# Android機器検出のリリース版修正（2026-11-10）

## 症状と修正

v0.1.0のAndroid APKで「機器の自動検出を利用できません」と表示され、PCの検出が動かない問題を修正。通常の検出モデルはAPKへ含まれており、モデルの未配置ではなかった。

- R8がprotobuf-liteのフィールド名を変更し、MediaPipeの設定の読み取りを壊していた。生成メッセージを保持するルールを追加。
- 実機の追加検証で、Floggerの呼び出し元探索もR8の最適化で失敗し、MediaPipeの静的初期化時にクラッシュすることを確認。FloggerとMediaPipe公式のJNIエントリポイントを保持。
- SDKの`LinkageError`は一般化した検出不可エラーとして返す。入力や生のSDKエラーはログへ出さない。
- ライブ検出が一度失敗すると停止したままになる処理を変更。失敗時は2〜30秒の待機を挟んで再試行する。タイムアウト後もネイティブ処理が残る間は追加のフレームを投入せず、遅れて返る古い検出枠を表示しない。

通常モデル・しきい値・12項目のチェック設定・公開施設API接続を維持。クラウド推論は追加していない。

## 検証

提出済みv0.1.0のソースを基準とする修正版で、`flutter analyze`と全282テストが成功（既存279件＋再試行に関する3件）。署名付き・R8適用のreleaseビルドを使って確認した。

Xperia XQ-FE44 / Android 16で、架空の無地画像だけを使う診断を実行：

| 対象 | 結果 | 時間 |
| --- | --- | --- |
| モデル初期化を含む撮影後画像の処理 | 成功 | 817ms |
| NV21フレーム・0度 | 成功 | 149ms |
| NV21フレーム・90度 | 成功 | 99ms |
| NV21フレーム・270度・Dart側ミラー処理 | 成功 | 99ms |

上記は1回の診断で、継続利用時の速度・精度・発熱を保証する測定ではない。診断の後、利用者から実際のPC検出が動いたとの確認を受領。検証専用の`POSTCHECK_DETECTOR_SMOKE`を有効にしたAPKと、通常の配布APKは区別し、配布APKではこの診断を実行しない。

診断を再実行する場合は、通常の署名・施設API・Maps設定に加えて`--dart-define=POSTCHECK_DETECTOR_SMOKE=true`を指定する。生成した無地画像のみを検出し、成功可否と処理時間だけを`POSTCHECK_DETECTOR_SMOKE`の行へ出力する。

## 配布

修正版はアプリversionName **0.1.1** / versionCode **2**、GitHub Release **v0.1.1**。既存v0.1.0と同じ署名を用いて上書き更新でき、アプリのアンインストールやデータ削除は不要。Maps設定はAPKに組み込み、インストールする利用者の設定は不要。

全機種での検出精度、Androidの地図・AI・共有の全工程、iOSの今回の更新は検証対象外。試験モデルとGemma本体は配布に含めない。

根拠：[protobuf-lite公式R8ルール](https://github.com/protocolbuffers/protobuf/blob/main/java/lite.md)、[MediaPipe公式JNI保持ルール](https://github.com/google-ai-edge/mediapipe/blob/master/mediapipe/java/com/google/mediapipe/framework/proguard.pgcfg)、[Flogger公式リポジトリの同種報告](https://github.com/google/flogger/issues/388)。

配布APKは`PostCheck-0.1.1-2.apk`（219,654,078 bytes）。SHA-256は`fbc5dfbe8f5a849e86b05b693fe610d47d64cea075d3e12c894787dafe836d42`。署名一致・debuggable false・既存Mapsキー一致・標準モデルのSHA-256一致・診断マーカーと試験モデルの非同梱を検査した。利用者の動作確認後にUSB端末が切断されたため、最終通常版APKの端末への再インストールは未実施。
