> **2026-11-10最新配信**：管理画面のStep 2をアプリ共通の確認12項目だけに整理し、既存Cloud Run・Hostingへ反映済み。既存詳細データは保持。配信状態と実際の検証範囲は[今回の配布記録](../docs/admin-check-items-deployment-20261110.md)を参照してください。

> **施設ルールの多言語説明（V18・2026-11-09）**：可否に加えて定型条件・対象エリア・施設確認済みの説明を4言語で表示。原文・翻訳変更時は再確認し、未確認の翻訳は公開配信しません。[仕様・検証・配置状態](../docs/multilingual-venue-rules-v18.md)。

# PostCheck 設定保存・復元API

> **V17：施設管理の委任確認と招待** — 施設ごとの権限・期限をrules層で管理し、個人連絡先専用欄を廃止。[仕様・API・配置結果](../docs/facility-access-v17.md)。個人設定バックアップは引き続き無効です。

> **最新：V8** — 施設ルールAPIはSignBridgeの大阪Cloud Run・Firestore・KMSへ配置済み。[接続・検証記録](../docs/implementation-v8.md)。個人設定復元のAPIは無効のまま。以下の未配置という記述は復元機能またはV5時点の履歴です。

> **最新スコープ**：今回の一般利用は匿名の公開施設・ルール取得。Google／Apple認証・組織限定配信・個人設定復元は後続に延期し、下記コードと接続手順を保持します。管理APIの認証・認可は外しません。クラウド未配置。[要件v0.4](../docs/requirements.md)。

> モバイルの近接候補・ON/OFFは[実装記録V6](../docs/implementation-v6.md)、地図キーの取得は[Maps設定手順](../docs/maps-api-setup.md)を参照。

> **施設ルールAPI追加（V5）**：`internal/rules`（ドメイン／公開処理）、`internal/ruleapi`（HTTP）、`internal/google/rules.go`（認証・暗号化保存）、`cmd/demo`（ループバック専用デモ）。[管理画面の起動](../admin_web/README.md) ／ [実装記録](../docs/implementation-v5.md)。以下の復元APIと同じ本番サーバーへ組み込んでいます。


2026-11-08：ユーザーの指定により **コード・接続設定まで作成。Google Cloudには未配置**。プロジェクト・請求先・IAMを変更していません。本番のGoogle/AppleログインやKMS/Firestoreとの疎通は未検証です。

接続先として既存 **SignBridge**（`gen-lang-client-0521532178`）の利用が決定しました。新規プロジェクトは不要。将来配置時の `GOOGLE_CLOUD_PROJECT` はこのIDを使います。現在はMaps設定から進め、認証・復元・サーバー配置は後続です。

画像解析とは独立したGoのサービスです。写真・投稿文・OCR・編集履歴・モデルを受け付けません。設定、企業ルール、登録ワード、明示的に記憶した選択の集計だけを保存します。

## 構造

- `internal/backup`：設定の入力契約、暗号化・復元ユースケース、Store / KeyWrapperポート。Google SDK非依存。
- `internal/google`：Firebase Auth / Firestore / Cloud KMSのアダプター。
- `internal/httpapi`：HTTP入力、認証、状態コード。UIDは検証済みトークンからだけ取得。
- `cmd/server`：実装の組み立て。
- Flutterは `CloudBackupPort` を介して接続。ローカル設定は `SettingsPort`。復元は全体を検証後、単一の設定レコードを置き換えます。

## 暗号化・アクセス制御

HTTPS → Firebase IDトークン検証（失効・無効化も確認）→ JSON許可リスト検証 → AES-256-GCM → Firestore。

保存ごとに暗号用の256bitデータ鍵とnonceを生成。データ鍵はCloud KMSで暗号化して、暗号文・nonceとともに保存します。KMSのマスター鍵をアプリやDBに置きません。UIDとschemaをAADに含めるため、別ユーザーのレコードへの暗号文・鍵の転用は復号で拒否します。

復元時のみサーバーが復号します。**運営も読めないE2E暗号化ではありません。** 正規の復号権限・実行権限を持つ主体はアクセスし得ます。本文・登録ワード・トークン・生SDKエラーをアプリログに出しません。Cloud Run等の標準リクエストログには時刻・ステータス・IP等の通信メタデータが残り得ます。

Firestoreのクライアントアクセスは `firestore.rules` で全拒否。Admin SDKはRulesを迂回するため、サービスアカウントのIAMを別に制限します。現状の試作は単一サービスアカウントでDBアクセスとKMS復号を行い、両権限が侵害された場合まで保護するものではありません。

## API

| 操作 | エンドポイント | 条件 |
|---|---|---|
| 取得 | GET /v1/backup | Bearer Firebase ID token |
| 新規保存 | PUT /v1/backup | `If-None-Match: *` |
| 更新 | PUT /v1/backup | 取得した `revision` を `If-Match` に指定 |
| 削除 | DELETE /v1/backup | `If-Match` 必須 |

PUTはschema 1の設定JSONそのもの。最大128KiB、ワード500件・各200文字、学習集計100区分まで。JSONの未知フィールドを拒否します。画像等を追加すると400。認証なし401、未作成404、競合409、前提ヘッダーなし428、基盤障害503。全応答 `Cache-Control: no-store`。書き込みの競合確認はFirestoreトランザクション内で実施します。

ログインだけではアップロードしません。ユーザーが保存・復元・削除を選んだ時だけ実行します。複数端末の自動マージはありません。GoogleとAppleを別アカウントで使った場合に自動統合する機能もありません。

## 将来配置するときの設定（今回は実行しない）

1. PostCheck専用Google Cloud/Firebaseプロジェクトと請求先を選ぶ。Cloud Run、Cloud Build、Artifact Registry、Firestore、Cloud KMS、Identity Toolkit APIを有効にする。
2. Firestore Nativeデータベースを東京等の選定リージョンに作成。`firestore.rules` を配布し、クライアントからの全アクセスを拒否。
3. Cloud KMSで同じ地域のKeyRingと対称暗号鍵を作成。鍵のローテーションを設定。古いバックアップの復号が必要な鍵バージョンを破棄しない。
4. 専用サービスアカウントを作成。`roles/datastore.user`、本人確認用 `roles/firebaseauth.viewer`、**対象KMS鍵だけ**の `roles/cloudkms.cryptoKeyEncrypterDecrypter` を付与。Owner/Editorや端末へのサービスアカウント秘密鍵配布はしない。
5. このフォルダのDockerfileからCloud Runへ配置。環境変数 `GOOGLE_CLOUD_PROJECT`、`KMS_KEY_NAME=projects/.../locations/.../keyRings/.../cryptoKeys/...`。最小インスタンス0、最大2、リクエストタイムアウト30秒を初期値とする。Cloud Run入口はFirebaseトークンをアプリで検証するため外部アクセス可。IAM用IDトークンとFirebase IDトークンを取り違えない。
6. Firebase AuthenticationでGoogle・Appleを有効化。AppleはApple Developer側のSign in with Apple設定、Team ID、Key/Service ID等が必要。秘密鍵はFirebase側の設定に置き、リポジトリへ入れない。
7. FirebaseにiOSアプリ `jp.kawakou.postcheck` を登録。`postcheck/config/cloud.example.json` を `cloud.local.json` に複製して公開クライアント設定を入力。アプリにサーバーの秘密鍵を入れない。
8. iOS `Info.plist` のURL TypesにGoogle iOS Client IDの逆順スキーム（`com.googleusercontent.apps.…`）を追加。XcodeでRunnerのSign in with Apple capabilityを有効にし、署名プロファイルを更新。今回は接続前なのでcapabilityとURLを架空値で追加していない。
9. `flutter build ios --release --dart-define-from-file=config/cloud.local.json` でビルド。ステージングを使う場合は同じ定義ファイルをステージ内で参照。
10. 架空のワードで2アカウント・2端末の保存/復元、他UID拒否、トークン失効、更新競合、削除、通信断、KMS拒否を実サービスで検証。公開前に利用規約・プライバシー説明、アカウント削除、App Check/流量制限・予算アラート、監査/運用を追加確認する。

復元APIのCloud Run実行は大会の実行基盤候補になりますが、**未配置のコードだけで大会条件を満たしたとは扱いません**。

## 検証

```sh
go test -race ./...
go vet ./...
```

ローカルテストでは鍵管理・保存・認証ポートを差し替えます。暗号化/復号そのものは実AES-GCMで実行。実際のFirebase/KMS/Firestore接続テストの代替ではありません。

公式資料：[KMSのエンベロープ暗号化](https://cloud.google.com/kms/docs/envelope-encryption)、[Firebase FlutterのGoogle/Apple認証](https://firebase.google.com/docs/auth/flutter/federated-auth)、[FirestoreのRulesとIAMの違い](https://firebase.google.com/docs/firestore/security/rules-conditions)。
