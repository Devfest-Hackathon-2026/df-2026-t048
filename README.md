# PostCheck

写真と投稿文を公開する前に、写り込み・連絡先・施設ルールなどの確認候補を示し、利用者が修正して保存・共有するアプリです。AIは候補を提示し、公開の最終判断は利用者が行います。

DevFest Hackathon 2026・チーム t048 の提出用ソースです。

**Androidの配布： [PostCheck 0.1.1（APK）](https://github.com/Devfest-Hackathon-2026/df-2026-t048/releases/tag/v0.1.1)**。ReleaseのAssetsからAPKを取得してください。Mapsキーは組み込み済みで、インストールする人の設定は不要です。Xperia（Android 16）で検出モデルの初期化・画像処理が成功し、利用者がPC検出を確認しました。[修正と検証範囲](docs/android-detector-fix-20261110.md)。

- モバイル：Flutter（iOS / Android）。UIは日本語・英語。
- 画像の文字認識・顔検出：ML Kit。物体検出：EfficientDet-Lite0 / MediaPipe。
- AI補助：端末内Gemma / LiteRT-LM。写真・文章・OCRをクラウドAIへ送信しません。
- 施設管理：Flutter Web、Go API、Cloud Run / Firestore / Cloud KMS。
- [稼働中の施設管理Web](https://postcheck-admin-0521532178.web.app)。管理操作には管理者の認証・権限が必要です。

## ディレクトリ

| 場所 | 内容 |
| --- | --- |
| `postcheck/` | モバイルアプリ、テスト、iOS / Androidのビルド設定 |
| `admin_web/` | 施設ルールの申請・審査・管理Web |
| `cloud/` | 施設ルールの公開・管理APIとローカルデモAPI |
| `packages/postcheck_rules/` | アプリ・管理Web共通のDart契約 |
| `ml/object_detection/` | 任意の物体検出の学習手順・コード・出典情報 |
| `docs/` | 要件、設計、実装・配布の記録 |

一般利用者向けWeb版は含めません。施設管理Webは含みます。個人設定のクラウド復元・一般利用者のログインは追加予定がなく、残っている旧接続コードは現在の利用フローでは使いません。

## ビルド・実行

検証環境はFlutter 3.44.5 / Dart 3.12.2。AndroidはAndroid SDKとJDK 17、iOSはMac・Xcode・CocoaPodsと実機署名が必要です。Go APIはGo 1.26以降を使います。

```sh
git clone https://github.com/Devfest-Hackathon-2026/df-2026-t048.git
cd df-2026-t048/postcheck
flutter pub get
bash scripts/setup_screen_detector.sh
```

標準の検出モデルは上のスクリプトで取得し、SHA-256を検証します。Gemma本体はGit・APKへ同梱せず、アプリ起動後にWi-Fiで取得します。取得中も基本チェックを使えます。任意の試験モデルの重み・学習画像はこの提出用リポジトリには含めません。

### Android

Android端末でUSBデバッグを有効にし、`flutter devices` で接続を確認します。キー不要の地図OFF設定で実行する例です。

```sh
flutter run --release -d DEVICE_ID \
  --dart-define=RULE_API_URL=https://postcheck-admin-0521532178.web.app \
  --dart-define=MAPS_ENABLED=false
```

地図ONの署名付きAPKは、Mapsキーと署名情報をPC内に設定してから作成します。

```sh
bash scripts/build_android_release_apk.sh 2
```

[Androidのキー・署名・APKの作成手順](docs/android-apk-github.md)。インストールする利用者側の環境変数設定は不要です。APKはソースとは別にGitHub Releasesへ添付する配布形式です。ソースのpushだけではReleaseは作成されません。

### iPhone

Xcodeで開発チームと署名を設定し、接続したiPhoneを指定します。キー不要の地図OFF設定で実行する例です。

```sh
bash scripts/run_iphone.sh DEVICE_UDID \
  --dart-define=RULE_API_URL=https://postcheck-admin-0521532178.web.app \
  --dart-define=MAPS_ENABLED=false
```

地図を使う場合は[iOS用Mapsキーの設定](docs/maps-api-setup.md)に従い、ローカルの設定ファイルをビルド時に読み込みます。iOS署名は各自のApple開発環境で設定してください。[詳細な起動・実機手順](postcheck/README.md)。

### 施設管理Webのローカルデモ

リポジトリのルートから、2つのターミナルで実行します。架空データ専用のデモです。

```sh
cd cloud
POSTCHECK_DEMO=1 go run ./cmd/demo
```

```sh
cd admin_web
flutter pub get
bash scripts/web.sh run config/demo.json
```

[http://127.0.0.1:5173](http://127.0.0.1:5173) で開きます。本番の施設管理APIは認証・認可を維持しており、デモ設定で公開しません。[管理Webの詳細](admin_web/README.md)・[APIの詳細](cloud/README.md)。

## 検証

各ディレクトリで実行します。

```sh
# postcheck/
flutter analyze
flutter test

# admin_web/
flutter analyze
flutter test

# packages/postcheck_rules/
dart pub get
dart analyze
dart test

# cloud/
go test -race ./...
go vet ./...
```

[提出用スナップショットと検証範囲](docs/submission-snapshot.md)に今回の結果を記載します。自動テスト、ビルド成功と、実機での動作確認は区別しています。

[運営の記載ルールとの照合](docs/submission-format-check.md)。説明ドキュメントの第5項には、Androidは上記Release、Webは施設管理Web、iOSのビルド実行方式はこのリポジトリのURLを記載します。

## 設定と公開範囲

APIキー・パスワード・サービスアカウント鍵・署名鍵・実環境の設定は含めません。`*.example.json` は各自のPCで `*.local.json` にコピーして設定します。ローカル設定や環境変数はGitへのpushで他のPCへ引き継がれません。

開発用リポジトリの過去のGit履歴、大量の画面キャプチャ・発表草稿・作業ログ・ビルドキャッシュは持ち込んでいません。実装記録には当時のローカル出力を指すリンクが残る場合があります。

この提出用リポジトリではGitHub Actions / GitHub Pagesは利用できません。手元でビルドします。[運営のリポジトリ案内](docs/submission-repository-guide.md)。

## 資料とライセンス

[要件](docs/requirements.md)・[製品概要](docs/product.md)・[アーキテクチャ](docs/architecture.md)・[施設ルールと位置情報](docs/architecture-rules-location.md)。

リポジトリのライセンスは[LICENSE](LICENSE)を参照してください。依存ライブラリ・SDK・モデル・フォント等には各権利者の条件が適用され、元のライセンス・NOTICE・出典を保持しています。[アプリ内のライセンス登録](postcheck/lib/app_licenses.dart)、[同梱の利用条件](postcheck/assets/licenses/)、[管理Web画像の生成記録](admin_web/asset_provenance.json)、[任意の学習データの出典](ml/object_detection/credits/)を参照してください。
