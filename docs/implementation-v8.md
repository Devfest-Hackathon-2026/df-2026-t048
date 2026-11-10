# V8 接続記録 — 施設ルール管理

更新日：2026-11-08。ユーザーの「進めてほしい」により、これまで延期していた施設ルール管理のクラウド配置を実施。個人設定のクラウド復元は引き続き対象外。

## 配置したもの

- 既存のSignBridgeプロジェクト `gen-lang-client-0521532178`。課金有効を確認。Firestore `(default)` はユーザーが作成した大阪 `asia-northeast2`。
- Cloud KMS：大阪の `postcheck` 鍵リング、対称暗号鍵 `rules`。Firestoreの施設レジストリはサーバー側でAES-GCM暗号化し、そのデータ鍵をKMSで包む設計。E2E暗号化ではなく、運営側で復号する。
- Cloud Run：`postcheck-api`（大阪、最小0・最大2）。専用サービスアカウントにFirestore、Firebase Authの参照、および対象鍵への暗号化／復号の権限を付与。`ENABLE_SETTINGS_BACKUP`は設定せず、個人設定復元APIは無効。
- Firebase Hosting：既存サイトとは別の `postcheck-admin-0521532178`。管理画面は https://postcheck-admin-0521532178.web.app 。同一オリジンの `/v1/**` をCloud Runに転送。Firebase Authenticationの許可ドメインを2件追加し、元のドメインは維持。
- 管理WebのFirebaseクライアント設定は `admin_web/config/app.local.json`（Git除外）。iPhone用 `postcheck/config/rules.local.json` に公開ルールAPIのURLを設定。Mapsキーは既存の設定を保持。
- 最初にGoogleログインした1人に対して、ユーザーが選択した運営（operator）権限を付与。本人から再ログイン後「PostCheck 運営」と表示されたと確認済み。
- iOS releaseをビルドし、接続iPhoneへインストール・起動。TestFlightにはアップロードしていない。

## 確認したこと

- APIの公開ルール一覧はHTTP 200で空配列。管理セッションの匿名アクセス401、管理一覧403、延期中のバックアップAPI404。管理の書き込みにもログインが必要。
- Firestoreの公開済みルールを確認し、クライアント直接の読み書き全拒否を確認。サーバーはIAMでアクセスする。
- Goテスト通過。管理Web Widgetテスト2件通過。管理WebリリースビルドとiOSリリースビルド成功。
- 現在の公開施設は0件。申請用の別Googleアカウントで架空施設を下書き保存し、Firestoreに暗号文・ラップ済み鍵だけが保存されることを確認。実クラウドのデータを復号して1件の下書きを確認。利用者は申請完了と報告したが、保存状態は `draft` で、APIログでは申請がHTTP 400。保存済みデータの必須項目を調べると住所・連絡先・公式サイト・根拠URLが未入力だった。申請・承認の完了とは扱わない。Googleログインと運営権限の画面表示は利用者確認済み。

## まだ確認できていないこと

- **実クラウドでの施設登録→申請→別アカウントによる承認→Firestore/KMS保存→iPhone反映**は未実施。ローカルのテスト成功だけでは実クラウドの保存成功と扱わない。
- 申請者と運営は別アカウント。運営は自分の組織の申請を承認できない。施設を登録するには別のGoogleアカウントでログインして申請する。
- 管理WebのGoogle Maps JavaScript APIキーは未設定。地図表示はなく、緯度・経度の手入力を使う。iPhoneのMapsキーは設定済み。
- 管理APIへの登録はGoogleログイン必須だが、未登録ユーザーも自分の組織として申請できる設計。商用公開に必要な招待制・登録制限、レート制限、監査運用、予算アラート等は未整備。1レジストリ最大100施設、暗号化前700KBという試作制限がある。
- 接続したGoogle Cloud/Firebaseは従量課金。KMSの鍵、Cloud Run、Firestore、Hosting、ビルドなどの費用は利用量と料金条件に依存する。
- iPhone実機での公開済み施設受信・GPS移動確認は未了。画像、投稿文、OCRは引き続き端末内で解析し、ルール取得APIへ送らない。
