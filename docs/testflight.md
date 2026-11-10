# PostCheck TestFlight配布

> **2026-11-10最新：ビルド11・内部配布完了**。施設ルール原文と投稿文の端末内AI照合を追加。13:36:15 JSTにアップロード成功。Appleの処理完了、説明文のSaved表示、既存内部グループ2名への追加とTesting表示を確認。TestFlightから更新できる内部配布設定を完了。

## 最新：0.1.0（ビルド11・内部配布済み）

- 施設が登録したルール原文と投稿文を端末内Gemmaで照合する処理を追加。投稿文の該当箇所・確認理由・関連するルールの実在する引用・施設名と版をレビューに表示する。「残す／隠す」で判断し、掲載許可・公開済みかをAIで断定しない。[仕様と検証範囲](venue-caption-review.md)。
- AIオフ・未準備・実行失敗・タイムアウト・原文なし・長さ上限超過では意味照合の未完了／未実施を明示する。登録ワード・連絡先などの基本チェック、ビルド10までの写真一括操作・近接施設選択を維持する。
- 配布元はmainの `e17fb9d4257b42ac2dbeed98e62f290e76e0a44c`。専用ステージングで、配布Bundle IDと試験モデル除外を除く追跡ファイル420件の一致を確認。ビルド設定はビルド10と一致するローカル定義を反映し、設定JSON自体は同梱しない。
- 今回の実装時に `flutter analyze --no-pub` は問題なし、`flutter test --no-pub` は全261件成功。配布作業で機能コードを変更せず、これらを再実行した結果とは扱わない。配布時のgitleaks差分確認・iOSアーカイブ・IPA書き出し・署名検証・同梱物検査は成功。
- 署名付きIPAは91,154,468 bytes。Bundle IDは `jp.kawakou.postcheck.beta`。Gemma本体・配布不可の `whiteboard_experiment.tflite`・ローカル設定JSONは非同梱。通常検出モデルは既存のSHA-256と一致。GemmaはWi-Fi自動取得を継続する。
- 2026-11-10 13:36:15 JSTにアップロード成功。App Store Connectでビルド11の処理完了とReady to Submitを確認。テスト説明文は下書きと一致しSaved表示を確認。13:51 JSTに既存の「PostCheck チーム内部テスト」（2名）のBuilds (7)にビルド11が入り、Testing表示であることを確認。TestFlightから更新できる内部配布設定を完了。
- 今回の新しいGemmaプロンプトの実機精度・速度・メモリ負荷、TestFlight更新後の操作は未検証。CLiteRTLM.frameworkのdSYM不足警告は継続するが、アップロードは成功。外部配布は変更していない。
- [配布記録](../output/postcheck-testflight-build11/summary.json)・[テスト説明文](../output/postcheck-testflight-build11/test-notes.txt)・[アップロード結果](../output/postcheck-testflight-build11/upload-result.txt)・[内部配布の表示確認](../output/postcheck-testflight-build11/distribution-verification.txt)。

> **ビルド10の履歴：内部配布完了**。写真候補の一括操作、カメラ見出しの中央配置、100m以内の最寄り施設の初回自動選択を含む。説明文のSaved表示と既存内部グループ2名への追加を確認。TestFlightから更新できる内部配布設定を完了。

## 履歴：0.1.0（ビルド10・内部配布済み）

- 写真候補に「すべて隠す／すべて残す」を追加し、その後の個別変更・確定済み加工の復元に対応。文章・手動マスクと企業の必須非表示ルールを保持する。[確認リスト](review-list.md)。
- カメラ見出しを中央配置へ変更。有効な測位と公開施設一覧がそろえば、100m以内の最寄り登録施設を初回から選択する。別施設への切替は独立した測位で2回確認し、手動選択・OFFを優先する。[施設選択の変更](camera-nearest-rules-20261110.md)。
- 一般利用者のアカウント不要・ログイン情報非収集を仕様v0.5の基本方針として明記。既存の一般アプリの認証・復元コードは有効化せず保持。施設管理Webの認証を維持する。[仕様](requirements.md#73-一般利用者のアカウントとログイン情報)。
- 配布元はmainの `799f0765d552ed01fa0efeffe48f66d4873371b1`。今回実行した `flutter analyze --no-pub` は問題なし、`flutter test --no-pub` は全235件成功。差分チェック・gitleaks、iOSアーカイブ・IPA書き出し・署名検証に成功。配布設定と試験モデル除外を除き、アプリ・共通ルールのビルド入力がプッシュ済みソースと一致することを確認。
- 署名付きIPAは91,151,121 bytes。Bundle IDは `jp.kawakou.postcheck.beta`。Gemma本体・配布不可の `whiteboard_experiment.tflite`・ローカル設定JSONの非同梱と、通常の検出モデルのソース一致を確認。GemmaはWi-Fi自動取得を継続。
- 2026-11-10 09:29:23 JSTにアップロード成功。App Store Connectでビルド10の処理完了とReady to Submit表示を確認。説明文は下書きとの一致とSaved表示を確認。09:44 JSTに既存の「PostCheck チーム内部テスト」（2名）へ追加し、ビルド10の詳細でGroup (1)・Internal 2を確認。TestFlightから更新できる内部配布設定を完了した。
- TestFlight更新後の実機操作・GPS移動は未検証。CLiteRTLM.frameworkのdSYM不足警告は継続し、このフレームワーク内のクラッシュのシンボル化に制限が残る。外部配布は変更していない。
- [配布記録](../output/postcheck-testflight-build10/summary.json)・[テスト説明文](../output/postcheck-testflight-build10/test-notes.txt)・[アップロード結果](../output/postcheck-testflight-build10/upload-result.txt)。

> **ビルド9の履歴：写真の全画面表示**。写真本体・全画面ボタンから開き、ピンチで拡大・縮小、ドラッグで移動できるビルド9を内部配布済み。既存グループ2名への配布とTesting表示を確認。Gemmaは引き続きWi-Fi自動取得。[写真表示の仕様](review-list.md)。

## 履歴：0.1.0（ビルド9・内部配布済み）

- 写真の全画面表示、1〜8倍のピンチズーム・ドラッグ移動、倍率リセット・閉じる操作を追加。加工プレビューと下書き・確認状態を保持する。日本語／英語に対応。
- 配布元はmainの `a3598e5`。実装時の静的解析とFlutter全216テストが成功。今回の配布ではiOSアーカイブ、IPA書き出し、署名、Bundle ID・バージョン・ビルド番号、既存検出モデルの一致を確認した。TestFlightからの更新後の実機操作は未検証。
- 署名付きIPAは91,144,884 bytes。Gemmaモデルとローカル設定JSONは含まない。配布不可指定の `whiteboard_experiment.tflite` は配布用コピーから除外し、IPAへの非同梱も確認した。通常のパソコン・スマホ等の検出モデルは維持。
- 2026-11-10 01:31:54 JSTにアップロード成功。01:37 JSTまでに既存の「PostCheck チーム内部テスト」（2名）への追加、グループのビルド9のTesting表示、テスト説明文のSaved表示を確認。TestFlightから更新できる内部配布設定を完了した。CLiteRTLM.frameworkのdSYM不足警告は継続し、このフレームワーク内のクラッシュのシンボル化に制限が残る。
- [配布記録](../output/postcheck-testflight-build9/summary.json)・[テスト説明文](../output/postcheck-testflight-build9/test-notes.txt)。外部配布は変更していない。

## 履歴：0.1.0（ビルド8・内部配布済み）

Gemmaの進捗を小数1桁の%と取得済みMB／合計MBで表示する。設定一覧からも確認可能。停止中も数値を表示し、取得100%と検証完了を区別する。ホームに戻る・画面ロックと、iPhoneのスワイプによる強制終了で挙動が異なることを案内する。ネイティブの取得方式は変更していない。

今回のFlutter静的チェックと全118テスト、架空50%取得の日本語／英語UI描画が成功。実機での背景取得完了は未検証。アーカイブ・署名検証に成功し、2026-11-09 15:35:22 JSTにApp Store Connectへアップロード成功。Appleの処理完了後、利用者が既存グループへ追加。15:54 JSTにビルド8の「PostCheck チーム内部テスト」への追加と、詳細のInternal 2名を画面で確認。内部配布設定が完了。外部配布は変更していない。[内部グループ追加の画面](../output/postcheck-testflight-build8/internal-distribution.png)。15:58 JSTにテスト説明本文が下書きと一致し、Saved表示で保存済みであることも確認。IPAは91,066,457 bytesで、Gemma本体・ローカル設定JSONは含まない。CLiteRTLM.frameworkのdSYM不足警告は継続。[配布記録](../output/postcheck-testflight-build8/summary.json)。

## 履歴：0.1.0（ビルド7・内部配布済み）


インストールの遅さを解消する最新ユーザー承認により、モデルを初回起動後のWi-Fi自動取得へ変更。手動ファイル追加は不要。準備中も基本チェックを利用でき、設定で進捗・停止・再開を確認する。

- 署名付きIPAは91,065,045 bytes、非圧縮アプリは176,820,397 bytes。同梱版ビルド6のIPAから96.03%削減。アーカイブ／IPAの`.litertlm`は0件、ローカル設定ファイルは含まない。
- 日本語／英語に限定したまま。モデル取得後の解析は端末内で実施し、入力写真・投稿文・OCRは配布元へ送信しない。
- 検証：Flutter静的チェックと全118テスト、Mac上の架空1MiBデータを使うネイティブURLSession連携5項目、iOSアーカイブ・配布署名・IPA検査が成功。実機でのバックグラウンド取得完了・Gemma推論・実インストール時間は未検証。
- [配布記録](../output/postcheck-testflight-build7/summary.json)・[テスト説明文](../output/postcheck-testflight-build7/test-notes.txt)。2026-11-09 14:59:42 JSTにアップロード成功。Appleの処理完了後、15:09 JSTに既存の「PostCheck チーム内部テスト」（2名）への追加と説明文のSaved表示を確認。TestFlightから更新できる内部配布設定を完了。外部配布は変更していない。[内部配布完了画面](../output/postcheck-testflight-build7/internal-distribution.png)。

- CLiteRTLM.frameworkのdSYM不足警告は継続。アップロードは成功したが、このフレームワーク内のクラッシュのシンボル化に制限が残る。

## 履歴：0.1.0（ビルド6・アップロード中断）

ビルド6は47%まで転送した時点で、ユーザーからインストールの軽量化を指示され、中断した。TestFlightの内部グループには追加していない。[中断記録](../output/postcheck-testflight-build6/summary.json)。以下は作成時点の記録。

Gemmaの同梱を維持し、最新指示の日本語／英語限定を反映して再作成する。中国語／韓国語のUI・専用OCR・AI言語指定・iOSリソースを除去。施設データの保存契約は保持する。環境変数・ローカル設定は引き続きGitから除外する。

今回のアプリの `flutter analyze --no-pub` は指摘なし、全115テストが成功。削除済みの言語ファイルが再利用するビルドキャッシュへ残らないよう、ステージング同期で除外設定を保持した `rsync --delete` を使用し、実際のステージングで削除を確認した。

## 履歴：0.1.0（ビルド5・配布見送り）

2026-11-09のユーザー指示により、現状の変更をmainへプッシュし、Gemma同梱版を配布署名してApp Store Connectへアップロードした。**13:43:27 JSTにアップロード成功**。AppleのProcessing表示を確認。その後にアプリを日英へ限定する最新変更が反映されたため、ビルド5は内部グループへ追加せず、ビルド6を配布対象とする。

- Gemma 4 E2Bを初回から使えるように同梱。モデル追加・USB転送の操作は不要。AI初期ONと既存OFF設定の維持、失敗時の基本チェック継続。
- 日本語・英語・簡体字中国語・韓国語の画面／OCR、施設の条件・対象エリア・確認済み翻訳表示、現在のSNS別共有・確認候補リストを含む。施設の翻訳データや新API・管理Webを本作業でクラウドへ配置したわけではない。
- 配布元コードはmainの `e773d81`。アプリ・共通パッケージのビルド入力がプッシュ済みコードと一致することを確認。
- 今回再実行：アプリ131件、管理Web8件、共通ルール6件のテスト成功。各静的チェック、Goのraceテスト・vetも成功。
- 署名付きアーカイブ／IPAのBundle ID `jp.kawakou.postcheck.beta`、0.1.0・ビルド5、Gemmaのサイズ・SHA-256、ライセンス・検出モデル、署名を確認。アプリ本体は非圧縮2,768,812,201 bytes、IPAは2,297,884,884 bytes。iOSの4GB上限内。
- 環境変数・ローカル設定・認証情報・モデル本体・ビルドログはGitへ含めていない。モデルは配布アプリにのみ含め、ローカル設定JSON自体はIPAに含めない。Maps等の従来のビルド設定はローカルから反映。
- CLiteRTLM.frameworkのdSYM不足警告は継続。アップロードは成功し、このフレームワーク内のクラッシュのシンボル化に制限が残る。
- 同梱版をTestFlightから入れた後のGemma推論・多言語OCR・実GPS移動・SNS受け取りは未検証。自動テスト・署名／配布成功と実機検証を区別する。
- [配布記録](../output/postcheck-testflight-build5/summary.json)・[テスト説明文](../output/postcheck-testflight-build5/test-notes.txt)。

## 履歴：0.1.0（ビルド4）

2026-11-08 19:01 JST、利用者の更新指示により最新ソースで再ビルドし、App Store Connectへアップロード成功。19:09 JSTにビルド4の「処理中」を確認。その後、再読み込みで管理画面が白画面になり、処理完了・内部グループ追加は未確認。テスターが更新可能になったとは扱わない。次の作業は、処理完了後に既存の「PostCheck チーム内部テスト」（2人）へビルド4を追加し、下記テスト説明文を保存すること。

- V15：実際の読み取り文字を見出しにした番号付き縦リスト、行ごとの「残す／隠す」、写真の枠との選択・スクロール連動。
- V14：X・LINE・Instagram・Threads向け共有メニュー、Instagramストーリーズ用9:16画像の端末内作成。MetaアプリIDは未設定のためOS共有を使用。各SNSでの受け取り・実投稿は未検証。
- 直前の実装検証はFlutter全99テスト通過・静的チェック問題なし。配布作業では機能コードを変更せず、テストの再実行はしていない。今回アーカイブ・配布署名・IPAの識別子／番号／検出モデル同梱を確認。
- 配布用Bundle IDは従来と同じ。Gemmaモデルとローカル設定JSONファイルはIPAへ同梱しない。Maps等のビルド設定は従来どおり反映。
- [配布記録](../output/postcheck-testflight-build4/summary.json)・[テスト説明文](../output/postcheck-testflight-build4/test-notes.txt)。CLiteRTLM.frameworkのdSYM不足警告は継続するが、アップロードは成功。

## 履歴：0.1.0（ビルド3）

2026-11-08 18:02 JST、最新の画像版をApp Store Connectへアップロード成功。Apple側の処理完了後、既存の「PostCheck チーム内部テスト」へビルド3を追加済み（2人）。ビルド詳細でグループ1件とテスト説明文の保存を確認。TestFlightから更新できる配布設定を完了。外部配布は変更せず、ビルド2のベータ審査待ちは継続。

- 約1m移動を目安とする前景測位と地図追従、日本語／英語、全画面カメラ・対応端末での広角／ズーム、PC・スマホ検出、輪郭マスク・ブラシ、写真／ファイル保存・共有を含む。
- 施設ルールの公開APIとMapsのローカル接続設定をビルドに反映。MapsキーのiOS許可対象へ配布Bundle IDを追加し、Maps SDK for iOS限定の制限は維持。
- 非免除暗号化なしの申告をInfo.plistへ追加。アプリ側で独自暗号化はせず、設定復元の暗号化はサーバー側。暗号化実装を追加した際は申告を再評価する。[Appleの説明](https://developer.apple.com/documentation/Security/complying-with-encryption-export-regulations)。
- 全77件のFlutterテスト通過。配布署名・アーカイブ・IPAのBundle ID／番号／検出モデル同梱を確認。TestFlightからインストール後の端末動作・GPS実移動は未検証。
- 作品・ホワイトボード・書類の専用検出は構想段階で、今回のビルドに追加していない。Gemmaモデルも同梱しない。
- [配布記録](../output/postcheck-testflight-build3/summary.json)・[テスト説明文](../output/postcheck-testflight-build3/test-notes.txt)・[内部配布完了画面](../output/postcheck-testflight-build3/internal-distribution.png)。CLiteRTLM.frameworkのdSYM不足警告は継続するが、アップロードは成功。

## 初回配布の履歴：ビルド2

2026-11-08。対象は画像版MVPと内カメラ回転修正まで。直近の発散で挙げた追加機能は含めない。

## 配布対象

- バージョン：0.1.0、ビルド：2。
- TestFlight用Bundle ID：`jp.kawakou.postcheck.beta`。
- 実機開発版の`jp.kawakou.postcheck`はVALIARKチームで明示的App IDとして登録できず、Appleに拒否された。実機開発版はワイルドカードの開発プロファイルで動作しているため、配布用を別IDにした。
- 通常のソースのBundle IDは変更していない。配布用ステージングのXcode設定だけ変更。開発版とTestFlight版は別アプリとなり、設定と追加したモデルは自動移行しない。
- 署名チーム・証明書・プロファイルはローカルのXcode管理。ソースに秘密鍵を置かない。

## 作成済み成果物と現在地

配布署名付きIPAの書き出し成功。ファイルの絶対パス・サイズ・SHA-256、アップロード状況は[配布記録](../output/postcheck-testflight/summary.json)を参照。

初回のアップロードはアプリ登録がなく停止したが、利用者がApp Store ConnectでPostCheckを作成し、アプリID `6832141859` を確認済み。2026-11-08 10:59 JSTにアップロード成功し、Appleから処理開始を確認。利用可能状態・輸出コンプライアンス・テスター設定は未確認（管理画面が空白で読み込めず）。[TestFlight管理ページ](https://appstoreconnect.apple.com/teams/1474cee9-a05e-49d6-bce7-5f9ad0048db5/apps/6832141859/testflight)。

## アプリ登録

App Store Connectの「アプリ」→「＋」→「新規アプリ」で作成する。

| 項目 | 値 |
| --- | --- |
| プラットフォーム | iOS |
| 名前 | PostCheck（使用済みの場合はPostCheck Beta） |
| プライマリ言語 | 日本語 |
| Bundle ID | jp.kawakou.postcheck.beta |
| SKU | postcheck-beta |

作成後、保存済みアーカイブとアップロード用ExportOptionsを使って再送信する。アプリの一般公開やテスターへの招待は別操作。ユーザー指定のない宛先への招待・公開リンクの作成はしていない。

## 次回の再ビルド

1. `postcheck/scripts/stage_build.sh`で同期対象外のキャッシュへソースをコピーする。
2. ステージング内のXcodeプロジェクトでRunnerのBundle IDを`jp.kawakou.postcheck.beta`へ変更し、承認済みの配布チームを設定する。ステージングを再実行すると元の開発設定へ戻ることに注意。
3. `flutter build ipa --release --build-number=<新しい番号> --export-options-plist=<ローカルのExportOptions.plist>`を実行する。書き出し方式は`app-store-connect`、自動署名。Flutterコマンドが終了コード0でもIPA書き出しに失敗する場合があるため、成果物とログの成功表示を確認する。
4. アーカイブの識別子・バージョン・番号を確認してから、`xcodebuild -exportArchive`の`destination=upload`で送信する。Xcodeに登録済みのアカウントを使用する。
5. Appleの処理完了、輸出コンプライアンス等の表示を確認する。アップロード成功だけではテスターが利用可能になったとは扱わない。

## テスト説明文の下書き

写真や投稿文の写り込み・公開内容を確認し、必要な部分を隠して共有する試作です。

- 「サンプル」で架空データを読み込み、確認候補→隠す／残す→修正後の再チェック→保存・共有を試してください。
- カメラの全画面表示、前後カメラ切替、写り込みの枠と注意、撮影・撮り直しを確認してください。
- 登録ワード、企業モード、個人学習の設定が反映されることを確認してください。
- Gemmaモデルはアプリに同梱していません。追加していない端末では、文字・顔・ルールによる基本チェックを利用できます。文脈AIの確認には、設定から対応する`.litertlm`モデルの追加が必要です。
- クラウド復元は接続先未配置のため利用できません。

端末内で写真・文章を解析します。検出漏れや誤った候補があり得るため、共有前に仕上がりを確認してください。不具合報告では、端末・操作手順・表示文言を中心に記録し、個人情報を含む写真は添付しないでください。

## 検証の範囲

今回の配布作業では機能コードを変更していないため、前回の22件テスト・実機確認と、今回実施したアーカイブ／配布署名の成功を分けて扱う。TestFlight版をインストールした後の動作確認は別途必要。起動画面のFlutterプレースホルダーについてビルド警告が出ているが、IPAの書き出しは成功している。

アップロード時、CLiteRTLM.frameworkのdSYMが同梱されていないという警告が出た。アップロード自体は成功しているが、このフレームワーク内のクラッシュのシンボル化は制限される可能性がある。
