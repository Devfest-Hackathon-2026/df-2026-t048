> **利用者・施設・最終適用の表示（2026-11-10）**：共通12項目のOR合成について、場所のルールで双方のON/OFFと最終適用を日英で確認できます。最新mainの設定・配信形式を維持して統合し、解析・全279テスト成功。実機・配布更新は今回未実施。[仕様・検証](../docs/effective-checks-or.md)。

> **施設ルールと投稿文の意味照合（2026-11-10）**：適用中の施設ルール原文と投稿文を端末内Gemmaで照合し、関連する一文とルールの引用をレビューに表示。基本の登録ワード照合も維持。AI未実行・原文なし・長さ上限超過では意味照合の未完了／未実施を明示します。今回の実機推論の精度・速度検証は未実施。TestFlightビルド11は既存内部グループ2名へ配布済み（[配布状態](../docs/testflight.md)）。[仕様・検証範囲](../docs/venue-caption-review.md)。

> **インストール軽量化（2026-11-09最新）**：Gemmaを本体から分離し、初回起動後にWi-Fiで自動取得。準備中も基本チェックを使えます。配布IPAは2,295,185,619→91,065,045 bytes（約96%削減）。[実装・検証範囲](../docs/fast-install-model.md)。

> **施設ルールの多言語説明（V18・2026-11-09）**：可否に加えて定型条件・対象エリア・施設確認済みの説明を日本語・英語で表示。原文・翻訳変更時は再確認し、未確認の翻訳は公開配信しません。[仕様・検証・配置状態](../docs/multilingual-venue-rules-v18.md)。

> **履歴：Gemma同梱**：同梱版の記録は[旧実装記録](../docs/bundled-gemma.md)。現在は冒頭のWi-Fi自動取得方式を採用し、ビルド7を配布対象とします。

> **言語範囲の変更（2026-11-09）**：最新ユーザー指示で中国語・韓国語のUI・OCR・AI応答指定・権限説明を撤去。アプリは日本語／英語、OCRは日本語／Latinに限定。中国語・韓国語はポスターで案内します。[変更と検証](../docs/app-languages-ja-en.md)。

> **確認リスト（V15）**：読み取った文字を見出しにし、候補を番号付きの縦リストへ変更。各行の「残す／隠す」と写真の枠を連動。[変更と検証](../docs/review-list.md)。TestFlightビルド4をアップロード済み、内部配布はAppleの処理完了待ち。[配布状態](../docs/testflight.md)。

> **SNS別共有（V14）**：X・LINE・Instagram・Threadsの共有先選択、ストーリーズ用9:16画像プレビュー、投稿文コピー、公式LINE宛ての文章引き継ぎを追加。[仕様・設定・検証範囲](../docs/social-sharing.md)。SNS側の文章取り込みは受信アプリ依存です。

> **位置情報の更新（2026-11-08）**：前景の位置ストリームと地図追従を約1m移動目安へ変更。1mの測位精度を保証する設定ではありません。施設切替の安定化・手動OFFを維持し、15秒周期の補助取得を継続。実移動時の精度・電池負荷は未検証。

> **英語対応（2026-11-08）** — 日本語／Englishの端末言語追従とアプリ内切替、英語の確認・編集・施設条件、Latin OCRと国際電話番号の候補検出。[範囲と検証](../docs/english-support.md)。

# PostCheck — 投稿前の炎上・情報漏えい対策 / Flutter MVP

> **撮影後チェック改善（2026-11-09）**：通常OCRにガンマ補正・タイル拡大を追加し、Gemmaは写真自体の確認を促す指示へ調整。途中結果の保持、現在の結果で確認する操作、同じ文字領域の根拠統合を追加。[設計](../docs/ocr-gemma-combined-design.md)／[実装・検証範囲](../docs/ocr-gemma-implementation.md)。精度改善の比較検証は別途必要。

> **画像の加工**：個人モードは「ぼかし／黒塗り」を選択可能。企業モードは黒塗り。加工をPNGの画素へ反映し、修正後は再チェックする。ぼかしは匿名化を保証しない。[文字認識の検証計画](../docs/ocr-improvement-plan.md)。

> **最新：V8** — iPhone用ローカルビルドを公開ルールAPIに接続し、実機にインストールしました。公開施設0件で、実施設の受信とGPS移動は未検証。[接続記録](../docs/implementation-v8.md)。

> **最新UI：V7** — Appleスタイルのテーマ、階層化した設定、主要操作の固定、iOSネイティブGlassを追加。[レビュー・変更・検証](../docs/ui-review-apple-v7.md) ／ [実装画面](../output/postcheck-ui-apple-v7/index.html)。

> **最新の仕様**：[要件v0.5](../docs/requirements.md)で近くの登録施設の自動取得・ルールON/OFFへ変更。Places不使用。2026-11-10承認：一般利用者はアカウント不要・ログイン情報を収集しない。ログイン・クラウド復元は追加予定なし。施設管理Webの認証は維持し、組織限定配信は後続。自動近接適用・OFF維持・撮影時の施設保持を実装済み。[実装記録V6](../docs/implementation-v6.md) ／ [Mapsキーの取得・設定](../docs/maps-api-setup.md)。iOS Maps表示は利用者確認済み。実GPSの移動・精度は現場検証が残っています。

> **V5追加**：施設一覧・地図接続・QR・施設ルールを反映しました。[実装記録と設定](../docs/implementation-v5.md)を参照。API未設定時は架空施設のデモ。地図キーは後日設定です。


> 2026-11-08更新：画像版V4の実装、企業モード、個人学習、クラウド復元の接続コードを追加。今回の範囲・検証状態は[実装記録](../docs/implementation-v4.md)を優先してください。クラウドはユーザー指定で未配置。動画は対象外。


このプロジェクトの現行開発対象です。[プロジェクトの入口](../README.md)、[全体要件](../docs/requirements.md)、[プロダクト概要](../docs/product.md)、[最新UI](../docs/design.md)、[実装状況と残タスク](../docs/roadmap.md)を参照してください。本書は現在の実装と実機での起動手順を扱います。V4の画像版画面と撮影中警告を実装しています。企業モード・個人学習・クラウド復元の追加分は[実装記録](../docs/implementation-v4.md)にまとめています。

投稿前の文章・写真に「ここ、公開して大丈夫？」という確認候補を出すiPhone向けアプリです。投稿者が「問題なし」「隠す」を選びます。公開可否の断定や自動投稿はしません。

## 実装範囲

- 文章のみ／写真のみ／両方のチェック。写真ライブラリ・カメラから入力。
- 日本語OCR、顔の位置、メール・電話番号、今後の告知への言及、任意の登録ワードの確認。
- 写真上の番号・枠・確認理由と、候補ごとの「問題なし」「隠す」「戻す」。
- 写真候補の「すべて隠す／すべて残す」と、選択後・再チェック後の1件ずつの変更。[一括選択の仕様と検証](../docs/review-list.md)。
- カメラ見出しを画面中央に配置し、有効な現在地から500m以内の最寄り登録施設のルールを自動選択。手動変更・OFFを優先。[変更と検証](../docs/camera-nearest-rules-20261110.md)。
- 写真本体または全画面ボタンから写真を大きく表示。ピンチで1〜8倍の拡大・縮小、ドラッグで移動、倍率リセットに対応。[仕様と検証](../docs/review-list.md)。
- 指で範囲を指定する手動黒塗り。文章中の対象文字の非表示。
- 修正を適用して、実際に修正された画像・文章を再チェック。
- 黒塗りを画素に反映し、EXIF/GPS等を引き継がないPNGとして共有・保存。
- 架空の名札と資料を端末内で描くサンプル。実際のML Kitでチェックします。
- Gemma 4 E2Bの画像対応モデルを初回起動後にWi-Fiで自動取得。準備中・失敗時も基本チェックを継続。モデル取得後のAI補助は端末内で行い、AIのON/OFFを設定で変更可能。

iPhoneに重点を置いたMVPです。AndroidプロジェクトもありますがAndroid実機では未検証です。SNS別の共有拡張・ブラウザ拡張、Cloud Storageの配布サービス、EmbeddingGemmaによる意味検索は含みません。設定復元用Cloud Run APIはコードあり・未配置です。2026年11月7日に保存した[大会ルール原本](../docs/hackathon/DF-Hack26-Kickoff-Slide.pdf)の開発ルール（p.35–36）にはGemini必須の記載はありません。一方、指定Google Cloud実行基盤のうち1つ以上をアプリの実行に使う条件は明記されています。現行MVPはこの実行基盤条件への対応が残っています。原本に基づく整理は[大会ルールメモ](../hackathon-rules.md)を参照してください。

## 技術と分離

| 担当 | 技術 |
| --- | --- |
| UI・アプリケーション・ルール | Flutter / Dart / Cupertino + 共通テーマ / UIKit Glass |
| 日本語OCR・顔の位置 | Google ML Kit |
| 端末内の画像・文章理解 | Google Gemma 4 E2B（Wi-Fiで自動取得） |
| 推論ランタイム | Google AI Edge LiteRT-LM |
| Flutterとの接続 | コミュニティ版 google_mlkit_* / litertlm |
| 画像マスク | Dart image・別isolateで実行 |
| 入出力 | camera / image_picker / file_picker / share_plus / iOS写真保存 |
| 設定復元（旧設計） | Firebase Authentication + Cloud Run (Go) + Firestore + Cloud KMS（未接続・未配置。追加予定なし） |

ML KitのFlutterブリッジは、日本語OCRをiOSで利用できる Text Recognition 0.16.0 / Face Detection 0.14.0 に固定。調査時点の1.0.x SPM版はiOSの日本語未対応のため採用していません。日本語SDKをPodfileで明示追加しています。litertlm 0.0.14 は公式LiteRT-LM v0.17.0のバイナリをSPMで取り込みます。pubspec.lock / Podfile.lockで依存関係を固定します。

- lib/domain/：FlutterやSDKに依存しないデータとポート。
- lib/application/：CheckDraft、確認ルール、AI入出力契約、文章マスク。
- lib/adapters/：ML Kit、Gemma、画像、設定、共有。
- lib/presentation/：画面と状態管理。
- lib/main.dart：実装の組み立て。

入力 → DraftInput → CheckDraft → PerceptionPort / ContextAnalysisPort → CheckReport → 画面で確認 → ImageProcessingPort / ExportPort、という流れです。チェックの中核を共有し、入出力・AI接続を差し替えられる設計です。

AIの指摘は既存OCRブロックID、原文の引用、画像全体にだけ紐づけます。AI生成の座標・未知IDは使いません。入力・設定の変更で以前の結果を破棄し、再チェックを必要とします。

## iPhoneで起動

検証環境：Flutter 3.44.5 / Dart 3.12.2、Xcode 27.2、CocoaPods。アプリの最小対象はiOS 16。Gemmaには対応モデル・十分な空き容量とメモリが必要です。

1. USB-CでiPhoneを接続し、ロック解除・Macの信頼・開発者モードを有効にします。
2. Xcodeで利用する開発チームを設定します。無料アカウントにはインストール数・期限の制限があります。既存アプリを自動削除する処理はありません。
3. 同期フォルダの属性による署名エラーを避けるため、次のスクリプトでMac内キャッシュへステージングして実行します。

~~~sh
cd /Users/kawakou/Documents/ChatGPT/GoogleHackathon/postcheck
bash scripts/run_iphone.sh DEVICE_UDID
~~~

ソースは ~/Library/Caches/PostCheckMVP/source にコピーされます。編集元はリポジトリです。リリースモードでインストール後はケーブルを外して使えます。開発用署名の有効期間内で利用してください。ビルド前のGemmaモデル取得は不要です。

## Gemmaモデル

インストールを軽くするため、約2.59GBのGemmaをアプリに同梱しません。AI補助は初期ONで、最初の画面を表示した後にWi-Fiで自動取得を始めます。既存のOFF設定と、利用者による取得停止を維持します。ファイル選択・USB転送は不要です。準備中も文字・顔・登録ワード・施設ルールの基本チェック、修正・書き出しを使えます。

設定→端末内AIで進捗、停止、再開・再試行を確認できます。iOSはOS管理のバックグラウンドURLSession、AndroidにはDownloadManagerの接続コードを用意しています。取得量自体は2,588,147,712 bytesです。省データモード・接続状況・空き容量・OSの制御によって待機・再取得になる場合があります。Androidのビルド／実機は未検証です。

[公開モデル](https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm)のサイズとSHA-256（181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c）を端末内で検証し、完了したファイルだけを推論に渡します。検証は少量ずつ読み、2.59GBをDartのメモリへ展開しません。取得済みの同じモデルはアプリ更新のたびに再取得しません。モデル用の保存領域はOSバックアップ対象外です。

写真・文章・OCR・登録ワードをモデル配布元やクラウドAIへ送信する処理はありません。モデルは公開URLへのGETのみで取得し、入力内容をリクエストの引数・本文・ログへ含めません。Apache 2.0のライセンス本文とアプリ内ライセンス登録を維持します。

~~~sh
bash scripts/run_iphone.sh DEVICE_UDID --dart-define-from-file=config/rules.local.json
# Gemmaの事前取得は不要。以下は架空の1MiBデータだけを使うネイティブ連携テスト。
python3 tool/test_model_download.py
~~~

署名付きビルド7のIPAは91,065,045 bytes（約91MB）、アプリ本体は非圧縮176,820,397 bytes。インストール時間そのものは実測していません。同梱版の履歴は[旧実装記録](../docs/bundled-gemma.md)、現在の仕様・検証・残る確認は[インストール軽量化](../docs/fast-install-model.md)、配布状態は[TestFlight記録](../docs/testflight.md)を参照してください。

## データの扱い

- 検査する写真・文章・OCR・社内辞書をクラウドAIへ送る経路や、自動的にクラウド推論へ切り替える処理はありません。
- 下書き・結果はメモリ上に保持し、再起動で消えます。写真選択機能が一時コピーを作る場合があります。
- 自前のOCR用一時画像は処理後に削除。共有用PNGは共有先が読み終えるまで必要なため次回起動時に削除します。
- モデル・設定はまず端末内に保存。iOSのOS自動バックアップとAndroidのアプリバックアップは無効化。クラウド設定保存の旧コードは保持していますが未接続・未配置で、2026-11-10の方針により追加予定に含めません。機種変更・アプリ削除時の設定・登録ワードの引き継ぎは提供しません。
- 共有操作では選んだ保存先・アプリへ内容が渡ります。写真ライブラリの既存の同期設定は本アプリの管理外です。
- [ML Kit](https://developers.google.com/ml-kit/terms)は入力と結果をGoogleへ送りませんが、SDKの診断メトリクス通信があります。外部通信ゼロを保証するものではありません。
- 生の入力・AI出力・SDKエラーに含まれる内容は、アプリのログに出しません。

## 検証

~~~sh
flutter analyze
flutter test
# 実機の日本語OCRを含む結合テスト（ステージング領域で実行）
flutter test integration_test/postcheck_device_test.dart -d DEVICE_UDID
# デバッガーが利用できない場合の、架空データだけを使う実機検証ビルド
flutter build ios --release --dart-define=POSTCHECK_SELF_TEST=true
~~~

検証ビルドはアプリのDocuments/postcheck-device-verification.jsonに結果を書き出します。通常ビルドでは検証は実行しません。

単体・画面テスト：日本語と絵文字、重なる文章マスク、AIの未知ID拒否、座標境界、PNGの黒塗り、入力変更による結果の無効化、古い非同期処理の破棄、書き出し内容、iPhone幅での基本操作。実機検証：日本語の名札・画面資料・メールのOCR、マスク・書き出し、修正後のOCRで元の連絡先が消えること。

2026-11-07の確認結果：flutter analyze問題なし、単体・画面テスト13件通過。iPhone 17 Pro / iOS 27.0.1で日本語OCR・マスク・再チェック・Gemma 4 E2Bによる画像と文章の推論を確認。架空データを使う一連の実機検証は約16秒で完了しました。精度・速度を一般化するベンチマークではありません。共有シートの保存先やSNS別の取り込み挙動は利用先により異なります。

Firebase/GoogleSignInとの重複リンクを避ける互換パッチは [vendor/README.md](vendor/README.md) を参照。

現行のML Kit CocoaPods版にはApple Siliconの新しいiOSシミュレーター向けarm64バイナリがないため、ネイティブ機能の結合検証は実機で行っています。
## 画面がある機器の検出（iOS）

初回ビルド前に `bash scripts/setup_screen_detector.sh` を実行してください。Google の EfficientDet-Lite0 モデルを取得して整合性を確認します。モデルは Git には含めず、検出は端末内で行います。対象は PC・スマホ・テレビなどの物体全体で、画面の輪郭を特定する機能ではありません。モデルがない場合は検出できない旨を表示します。

実行APIはTensorFlowLiteTaskVision 0.4.3。Task Library対応の4出力版モデルを使用します。写真・BGRA入力での実機検証とSDK競合への互換処理は[検証記録](../docs/screen-device-detection.md)を参照してください。既存の地図・施設API設定を維持する実機ビルドでは、`scripts/run_iphone.sh DEVICE_UDID --dart-define-from-file=config/rules.local.json`を使用します。

## 輪郭マスク・ブラシ編集

写真確認画面の「範囲を隠す」から多角形・ブラシ・消しゴムを利用できます。頂点の独立移動、拡大・移動、太さスライダー、取り消し／やり直しに対応。PC・スマホの撮影後検出では、取れる場合に四隅の候補を表示します。詳細・検証範囲は [輪郭マスク編集](../docs/freeform-mask-editor.md)。
