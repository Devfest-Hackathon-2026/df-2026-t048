# 提出時の記載ルールとの照合

2026-11-10。運営の[提出物・提出ルール](https://docs.google.com/document/d/1r2QRvMQbcJqhmYAEKAFTN9Co_zsJzvFhxfuS1wx1FJE/edit)の公開テキストを読み、READMEに関係する指定と照合した。README自体の構成は原則自由で、ネイティブアプリの提出方法に応じた指定がある。

| 対象 | 運営指定の要点 | このリポジトリの対応 |
| --- | --- | --- |
| READMEの構成 | 一律の見出し・文体テンプレートは指定されていない | 製品概要・構成・起動手順・検証・利用条件を記載 |
| 直接実行できるAndroidアプリ | 実行ファイルをチームのGitHub Releasesへ添付 | 署名付きAPKを `v0.1.1` のReleaseへ添付する配布方式 |
| 直接配布しにくいiOSアプリ | ルートREADMEにビルド・起動方法を記載 | 環境・署名準備・モデル準備・実行コマンドを記載 |
| Web | 公開URLを説明ドキュメントの第5項に記載 | 施設管理WebのURLをREADMEにも記載 |
| リポジトリの運営案内 | 稼働URLの記載、秘密情報を含めない、Actions / Pagesを使わない | URLとローカルビルド手順を記載し、秘密情報・開発履歴を除外 |

Google Docsの説明ドキュメントはREADMEとは別に指定テンプレートへ記入する必要がある。本確認はREADME・配布方法の照合であり、説明ドキュメント全体、動画、スライド、著作物利用シート、提出フォームの完成・提出を確認したものではない。

## 説明ドキュメント第5項へ転記する情報

- Android： https://github.com/Devfest-Hackathon-2026/df-2026-t048/releases/tag/v0.1.1 。ReleaseのAssetsからAPKをインストール。Android 8.0以上、インターネット接続、地図はGoogle Play開発者サービスが必要。Mapsキーの設定は不要。Gemmaは起動後にWi-Fiで約2.59GBを取得し、その間も基本チェックを利用できる。
- 施設管理Web： https://postcheck-admin-0521532178.web.app/ 。管理操作には管理者の認証・権限が必要。
- iOSのビルド実行方式： https://github.com/Devfest-Hackathon-2026/df-2026-t048 。ルートREADMEの手順を参照。

## キーの確認範囲

Androidは配布APKのManifest内のMapsキーとクラウド上の制限キーの一致、配布署名と登録SHA-1の一致を確認した。公開中の管理Webも配信されるMaps設定とWeb制限キーの一致を確認し、正しい公開サイトのRefererでGoogle MapsのスクリプトがHTTP 200で返ることを確認した。キー文字列はこの文書に記載していない。

これらはキーの設定・組み込みの確認であり、Android実機やブラウザ上での地図描画の新規確認とは区別する。署名の秘密鍵・パスワードはPC内に保持し、APKにもWebにも含めない。
