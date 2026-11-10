# PostCheck — Maps APIキーの取得・設定

> **2026-11-10配布時点の確認**：Androidの配布APKは地図ONで、署名証明書・パッケージ名に制限したAndroid用キーを組み込み済み。管理Webの公開 `maps.local.js` も、公開ドメインとMaps JavaScript APIに制限したWeb用キーと一致することを確認した。公開ファイルとGoogle MapsのスクリプトはHTTP 200。以下の「後で対応」「未設定」は当時の記録であり、現在の配布設定はこの追記を優先する。アプリやブラウザで使うMapsキーは配布物から読み取れるため利用先制限で保護し、Gitのソースには含めない。署名の秘密鍵・パスワード・サービスアカウント鍵は配布物にも含めない。新規ビルド手順は [Android配布](android-apk-github.md)、一般利用者向けWeb版ではなく施設管理Webが対象。

> 2026-11-10管理Web更新：利用者指示で既存Hostingの `MAPS_ENABLED=true` を反映済み。Web専用キー `postcheck-admin-web` をMaps JavaScript APIと本番2ドメイン（`postcheck-admin-0521532178.web.app`／`.firebaseapp.com`）のHTTPリファラーに限定し、Git外の `admin_web/config/app.local.json` へ保存した。HostingのReferrer-Policyは `strict-origin` とし、URLのパス・クエリを送らずオリジンだけでキー制限を確認する。Webビルド成功、公開9ファイルのSHA-256一致、公開オリジン上のブラウザで地図タイルの描画とMapsエラーなしを確認。認証後の施設編集・保存の再試験は今回行っていない。以下のWeb未設定という記述は11月8日時点の履歴。

2026-11-08。現在地は端末GPS、自前登録施設との照合は端末内です。**キーが必要なのはGoogleの地図表示**です。Places API、Gemini API、Firebase／Apple認証は今回の設定対象ではありません。写真・OCRをGoogleへ送る設定でもありません。

接続先はユーザー指定の既存プロジェクト **SignBridge**（`gen-lang-client-0521532178`）。Google Cloud上の旧企画名をそのまま利用し、アプリ名はPostCheckを維持します。2026-11-08にユーザーがMaps SDK for iOSを有効化し、`postcheck-ios` キーを作成・ローカル設定へ入力済み。iOSアプリ制限は `jp.kawakou.postcheck`、API制限はMaps SDK for iOSだけに調整しました。設定を含めた実機版の再ビルド・インストール・起動は完了。地図の実表示は利用者確認済み。Web用キー、公開APIのクラウド配置は未完了です。

## 作るキー

| 用途 | 有効にするサービス | アプリケーションの制限 | 保存する設定 |
| --- | --- | --- | --- |
| 今のiPhone開発版 | Maps SDK for iOS | iOSアプリ、Bundle ID `jp.kawakou.postcheck` | `postcheck/config/rules.local.json` の `GOOGLE_MAPS_API_KEY` |
| TestFlight版に後で反映する場合 | Maps SDK for iOS | 実際の配布Bundle ID `jp.kawakou.postcheck.beta` を別キーまたは許可対象に登録 | 配布用ローカル設定。今回はアップロードしない |
| Web管理画面の地図 | Maps JavaScript API | ウェブサイト／HTTPリファラー | `admin_web/config/maps.local.json` の `GOOGLE_MAPS_WEB_API_KEY` |
| Androidを後で検証する場合 | Maps SDK for Android | Androidアプリ、`jp.kawakou.postcheck` ＋署名証明書SHA-1 | Gradleプロパティ `POSTCHECK_MAPS_API_KEY` |

iOS・Web・Androidのキーは分けます。キーを作るだけではAPIは有効にならないため、サービスの有効化とキーのAPI制限を両方設定します。[Google公式のFlutter設定](https://developers.google.com/maps/flutter-package/config)、[キーの制限](https://developers.google.com/maps/api-security-best-practices)

## 1. 共通の準備

1. [SignBridgeのGoogle Cloud Console](https://console.cloud.google.com/apis/dashboard?project=gen-lang-client-0521532178)を開く。確認済みのアカウントは `kawakou0910@gmail.com`。プロジェクトIDが `gen-lang-client-0521532178` であることを確認する。新規プロジェクトの作成は不要。
2. 標準Mapsキーを使うプロジェクトに請求先を関連付ける。今回はここまでのクラウド操作を代行していない。
3. 「APIとサービス」→「ライブラリ」で利用するサービスを検索して有効化する。
4. 「Google Maps Platform」→「キーと認証情報」（または「APIとサービス」→「認証情報」）→「認証情報を作成」→「APIキー」を選ぶ。
5. 作成時／編集画面でAPI制限とアプリケーション制限を設定し、保存する。反映に数分かかる場合がある。

標準キーでは請求先設定が前提です。地図を使う範囲・利用量に応じた課金条件は有効化時に確認してください。[iOS公式設定](https://developers.google.com/maps/documentation/ios-sdk/get-api-key)

## 2. iPhone用（最初に設定するもの）

1. `Maps SDK for iOS` を有効化。
2. APIキーを作り、名前を例として `postcheck-ios-dev` にする。
3. 「アプリケーションの制限」は「iOSアプリ」。Bundle IDに `jp.kawakou.postcheck` を追加する。
4. 「APIの制限」は「キーを制限」、対象を `Maps SDK for iOS` にする。
5. 作成したキー文字列を、ローカルファイル `postcheck/config/rules.local.json` に入力する。チャットやGitには貼らない。

```json
{
  "RULE_API_URL": "",
  "MAPS_ENABLED": true,
  "GOOGLE_MAPS_API_KEY": "取得したiOS用キー"
}
```

`RULE_API_URL` が空の間は架空施設デモです。Mapsキーを設定しても、管理画面で登録した施設のクラウド配信まで自動接続されるわけではありません。公開ルールAPIの配置後にHTTPSのベースURLを入れます。

設定はビルド時に取り込むため、アプリの再ビルド・再インストールが必要です。コード内にキーを直書きする必要はありません。

```sh
cd /Users/kawakou/Documents/ChatGPT/GoogleHackathon/postcheck
bash scripts/run_iphone.sh 00008150-001919022620401C --dart-define-from-file=config/rules.local.json
```

事前にFlutterをPATHへ入れ、Xcodeの開発用署名チームを設定します。この端末では開発チームはVALIARK。ビルド用ステージはMacのキャッシュ内です。今回の実機版は `jp.kawakou.postcheck`、過去のTestFlight版は `.beta` が付く別IDなので取り違えないでください。[iOSキーの公式手順](https://developers.google.com/maps/documentation/ios-sdk/get-api-key)

## 3. Web管理画面用（地図を使う場合）

1. 同じプロジェクトで `Maps JavaScript API` を有効化。
2. 別のキー `postcheck-admin-web-dev` を作る。
3. 「アプリケーションの制限」は「ウェブサイト」。ローカル検証先として次を許可する。
   - `http://127.0.0.1:5173/*`
   - `http://localhost:5173/*`
4. 「APIの制限」は `Maps JavaScript API` のみ。
5. `admin_web/config/maps.local.json` に入力する。本番公開後は本番ドメインを使う別キーへ分ける。

```json
{
  "POSTCHECK_DEMO": true,
  "RULE_API_URL": "http://127.0.0.1:8787",
  "MAPS_ENABLED": true,
  "GOOGLE_MAPS_WEB_API_KEY": "取得したWeb用キー"
}
```

```sh
# ターミナル1
cd /Users/kawakou/Documents/ChatGPT/GoogleHackathon/cloud
POSTCHECK_DEMO=1 go run ./cmd/demo
```

```sh
# ターミナル2
cd /Users/kawakou/Documents/ChatGPT/GoogleHackathon/admin_web
bash scripts/web.sh run config/maps.local.json
```

既存の5173番サーバーを使っている場合は先に終了して再起動します。管理操作は当面ローカルデモで、Googleログインの設定は不要です。Web用キーはブラウザに届く値なので、秘匿だけに頼らず利用先制限を設定します。[Webキーの公式手順](https://developers.google.com/maps/documentation/javascript/get-api-key)、[リファラー制限](https://developers.google.com/maps/api-security-best-practices)

## 4. Android用（後で対応する場合）

1. `Maps SDK for Android` を有効化し、Android用の別キーを作る。
2. アプリケーション制限を「Androidアプリ」にし、パッケージ名 `jp.kawakou.postcheck` と、実際に使う署名証明書のSHA-1を指定する。
3. SHA-1はAndroidプロジェクトで `./gradlew signingReport` を実行して確認する。デバッグ用とリリース用は証明書が異なる。Play App Signingを使う場合は配布版の署名証明書を使う。
4. API制限を `Maps SDK for Android` にする。
5. ローカルのGradleプロパティ（例：`~/.gradle/gradle.properties`）に `POSTCHECK_MAPS_API_KEY=取得したAndroid用キー` を設定。ビルドのDart定義では `MAPS_ENABLED=true` を指定する。

Androidの実機動作はまだ未検証です。iOS用キーを使い回しません。[Androidキーの公式手順](https://developers.google.com/maps/documentation/android-sdk/get-api-key)

## キー設定後の確認

- iPhoneで「施設を変更」を開き、地図と登録施設のピンが表示される。
- 「現在地を使う」で利用中の位置情報を許可し、実際の登録座標の近くで候補が出る。初期案は100m以内・精度50m以内・連続2測位（約5m移動目安の購読＋更新が止まった際の15秒周期の補助取得）。施設への入館を証明するものではない。
- キーなしでも「架空の施設に近づく」でON→OFF→離脱→再進入の操作を試せる。この操作はGPS実測ではない。
- 施設ルールOFFでも顔・連絡先チェックが継続する。
- 地図が表示されない場合は、対象プロジェクト、API有効化、請求先、キーの対象API、Bundle ID／リファラー、`MAPS_ENABLED`、再ビルドの有無を確認する。

`*.local.json` と生成する `maps.local.js` はGit除外済み。サービスアカウント秘密鍵やApple署名キーはこの設定へ入れません。
