> **2026-11-10地図表示**：本番管理WebのMapsを有効化済み。Web専用キーを本番ドメインとMaps JavaScript APIに制限。設定・検証は[Maps設定記録](../docs/maps-api-setup.md)を参照。

> **2026-11-10最新配信**：管理画面のStep 2をアプリ共通の確認12項目だけに整理し、既存Cloud Run・Hostingへ反映済み。既存詳細データは保持。配信状態と実際の検証範囲は[今回の配布記録](../docs/admin-check-items-deployment-20261110.md)を参照してください。

> **施設ルールの多言語説明（V18・2026-11-09）**：可否に加えて定型条件・対象エリア・施設確認済みの説明を4言語で表示。原文・翻訳変更時は再確認し、未確認の翻訳は公開配信しません。[仕様・検証・配置状態](../docs/multilingual-venue-rules-v18.md)。

# PostCheck 施設ルール管理（Flutter Web）

> **最新：V17** — 公式窓口の委任確認と施設単位の責任者／担当者招待を追加。個人の氏名・電話・メールをフォームで集めません。[権限確認・招待・検証](../docs/facility-access-v17.md)。V16以前の連絡先収集・組織IDだけの編集権限は本仕様で置き換えます。

> **最新：V16** — iwaseの申請者・運営UIを既存Go APIへ統合し、既存の[管理画面](https://postcheck-admin-0521532178.web.app)へ反映しました。運営の操作権限・自動保存・審査画像の非公開化を修正。[変更・検証・制限](../docs/admin-integration-v16.md)。下記V5/V8の未配置という記述は履歴です。Web Mapsの現在の設定は冒頭の更新記録を参照してください。

> **最新：V8** — 施設ルール管理WebとAPIはユーザー承認でクラウドに配置しました。[管理画面](https://postcheck-admin-0521532178.web.app) ／ [配置と検証状態](../docs/implementation-v8.md)。以下はV5時点のデモ・準備手順で、未配置という記述は履歴です。

> **提供範囲の更新**：一般利用者は公開ルールの匿名閲覧で利用し、Google／Apple認証・組織限定配信・復元は後続に延期。管理Webは当面ローカルデモ。下記の本番認証設定は後続手順として保持し、管理APIを匿名公開しません。[要件v0.4](../docs/requirements.md)。

> モバイルの近接候補・ON/OFFは[実装記録V6](../docs/implementation-v6.md)、地図キーの取得は[Maps設定手順](../docs/maps-api-setup.md)を参照。

MATRAICEのNotion派生デザインに沿った、組織担当者と運営担当者の管理画面です。施設登録 → ルール編集 → 公開プレビュー → 申請 → 審査・承認／差し戻し／公開停止を実装しています。クラウドとMapsキーは未設定です。

## Macで試す

ターミナル1（API、架空データ専用）：

```sh
cd /Users/kawakou/Documents/ChatGPT/GoogleHackathon/cloud
POSTCHECK_DEMO=1 go run ./cmd/demo
```

ターミナル2（管理画面）：

```sh
cd /Users/kawakou/Documents/ChatGPT/GoogleHackathon/admin_web
flutter pub get
bash scripts/web.sh run config/demo.json
```

http://127.0.0.1:5173 を開きます。「組織担当者としてデモを開く」で登録・申請し、ログアウト後「運営担当者としてデモを開く」で根拠を確認し承認します。デモAPIは127.0.0.1にだけバインドし、CORSも同じMacの5173番だけを許可します。デモトークンは本番サーバーでは受け付けません。

ローカルデモの保存先はOSキャッシュの `PostCheckMVP/rules-demo.json`。平文の架空データ専用です。実際の連絡先・秘密語は入力しないでください。`POSTCHECK_DEMO_DATA` で保存先を変更できます。

`bash scripts/web.sh build config/demo.json` でリリースビルドできます。生成物を外部公開する際にはデモ設定を使わないでください。

## 後で接続する設定

`config/app.example.json` を `config/app.local.json` にコピーして入力します。`*.local.json` はGit除外済みです。

- Firebase AuthのWebクライアント設定を入力し、Googleログインと許可ドメインを設定。
- `POSTCHECK_DEMO=false`。本番の権限はサーバーの `ruleMembers/{Firebase UID}` が決めます。`org` と `operator` は信頼できる運営がAdmin SDK/Consoleから付与し、クライアントから書けません。
- 未確認の利用者は下書き作成まで。公式窓口が委任した責任者、またはその責任者が招待した担当者だけが対象施設を編集・申請できます。同じ組織IDだけでは権限を付けません。
- `RULE_API_URL` は同一オリジンの場合は空文字。`firebase.example.json` の `/v1/**` をCloud Runへ、その他をWebへ振り分ける例を用意しています。別オリジンの任意CORSは本番APIで開放していません。
- Mapsを使う場合だけ `MAPS_ENABLED=true` と `GOOGLE_MAPS_WEB_API_KEY` を設定。Web用のキーをMaps JavaScript APIと管理画面のHTTPリファラーに制限します。モバイルとは別キーを使います。
- `scripts/web.sh` はキー付きの `web/maps.local.js` を生成してビルドします。ブラウザ用APIキーはユーザーから見える値です。サーバーの秘密鍵は入力しません。
- 未設定時は地図の代わりに座標入力を表示します。登録施設のピン選択が対象で、Places自由検索は含みません。

クラウド側の準備は [cloud/README.md](../cloud/README.md)。**今回は配置していません。** Firebase Auth、Firestore、KMS、Mapsの実サービス疎通は接続後に確認します。

## テスト

```sh
flutter analyze
flutter test
# ローカルAPIを起動して、DartとGoの実際のJSON契約を確認
cd ../packages/postcheck_rules
dart run tool/demo_smoke.dart
```

保存失敗時の入力保持、離脱確認、公開対象の確認チェック、申請後の画面復帰をWidgetテストで検証。APIでは他組織拒否、申請版固定、更新競合、承認・差し戻し・公開停止を検証しています。
