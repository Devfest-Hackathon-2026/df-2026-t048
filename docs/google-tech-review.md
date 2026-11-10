# PostCheck — Google技術の活用とアーキテクチャの確認

> 2026-11-08追記：以下は以前の構想・技術評価。画像版V4、ライブ入力、企業モード・学習、Cloud Run/Firestore/KMS復元APIの追加後の構成は[技術構成](architecture.md)と[実装記録](implementation-v4.md)を優先。クラウドは未配置。


確認日：2026-11-07。現行ソース・既存の実機検証記録・Googleの公式資料を確認したものです。新しいビルド・性能測定は実施していません。「尖り」は採用目的と技術的な特徴に対する本プロジェクトの評価であり、利用者数や審査加点の統計ではありません。

## 結論

**現状でも、Gemma 4 E2B × LiteRT-LMというGoogle AI Edgeの技術を中核に使えています。** 特徴は、写真と文章をクラウドAIへ送らず、iPhone内で文脈確認を補助することです。Google技術を使う目的が、投稿内容のプライバシーという要件につながっています。

FlutterとML Kitはアプリの基盤として重要ですが、それらの採用名だけで技術的な独自性を説明するのは弱いと判断します。説明の中心は、端末内マルチモーダル推論と、ライブの軽い検出・撮影後の詳しい検査を分ける設計に置きます。

## 現在の構想図

![現状構想と実装状態](../output/postcheck-architecture-v2/postcheck-architecture-v2-preview.png)

[高解像度PNG](../output/postcheck-architecture-v2/postcheck-architecture-v2.png) ／ [SVG](../output/postcheck-architecture-v2/postcheck-architecture-v2.svg) ／ [Mermaidソース](../output/postcheck-architecture-v2/architecture.mmd)

## 技術ごとの評価

| 技術 | 状態 | 独自性への寄与という観点での評価 | このプロダクトでの必要性 |
| --- | --- | --- | --- |
| Gemma 4 E2B | 接続実装と既存実機推論記録あり | 高い。端末で画像・文章の文脈を扱う中核 | 写り込みと投稿文に対し、文字の一致だけでは出せない確認候補を補助 |
| Google AI Edge LiteRT-LM | 実装あり | 高い。モデルを端末で実行する基盤 | iPhone内で推論を動かし、端末の計算資源を使う |
| ML Kit OCR / Face Detection | 静止画は実装・既存確認あり。ライブ経路は未実装 | 技術単体の珍しさより、役割分担の妥当性が強み | 文字と位置・顔の位置を得る。Gemmaに正確な座標を生成させない |
| Flutter / Dart | 実装あり | 基盤として有効。単独で尖りを説明する材料にはしない | 入出力・中核ロジックを共通化し、SDK接続を境界で分離 |
| Cloud Run / Cloud Storage | 未導入の候補 | 一般的な構成。必要な運用上の役割を設計して使う | 一般ルール・モデル配布情報の提供候補。大会条件の対応は残件 |
| EmbeddingGemma 2 | 新たに比較した拡張候補。未採用 | 教育を主目的にするなら意味のある追加候補 | 端末内のSNSガイド・教材を意味検索し、説明の根拠を取得 |

Gemmaはモデル、LiteRT-LMは実行基盤であり、セットで1つの推論機能を成立させています。独立した機能が2つあるかのように数を水増しして説明しません。

## ソースで確認できたこと

- [local_gemma.dart](../postcheck/lib/adapters/local_gemma.dart) は画像バイト列と投稿文・OCRを渡し、端末内の `.litertlm` を使用します。クラウドAIのクライアントや自動フォールバックを持ちません。
- 同ファイルのエンジン設定は `backend: GPU`、`visionBackend: CPU`。アプリでNPUを利用しているとは説明しません。ランタイム一般の対応範囲と、このアプリでの設定を分けます。
- [ai_contract.dart](../postcheck/lib/application/ai_contract.dart) で実在のOCR IDと原文引用を検証し、AIに座標を作らせない契約にしています。
- [既存の実機記録](../output/postcheck-mvp-verification/device-ai-verification.json) には、写真・文章を含むGemma推論と加工後の再チェックを完了した記録があります。一般的な精度・低遅延の保証ではありません。
- [ports.dart](../postcheck/lib/domain/ports.dart) に知覚・文脈解析・画像処理・出力の境界があります。ライブ用の契約とSNS別アダプターはまだありません。
- FlutterからのML Kit / LiteRT-LM接続にはコミュニティ製ブリッジを利用しています。Google公式のFlutter製品が一式そろっていると誤認させない説明にします。

## 公式資料との対応

GoogleはGemma 4を画像と文章を扱うモデルとして案内し、E2B / E4Bをモバイル・エッジ向けに位置づけています。本プロダクトのオンデバイスの写真・文章確認という用途と合います。[Gemma 4モデルカード](https://ai.google.dev/gemma/docs/core/model_card_4)

LiteRT-LMはiOSを含む複数環境でのモデル実行と、マルチモーダル処理・ハードウェア活用を扱う基盤です。ただし資料にある他モデル・他端末の性能値をPostCheckの速度として転記しません。[LiteRT-LM公式概要](https://developers.google.com/edge/litert-lm/overview)

ML Kitは画像・動画の文字認識と顔の位置検出に使えます。静止画処理の採用は確認済みで、動画のAPI対応だけをもって、本アプリのライブ経路が完成しているとは扱いません。[文字認識](https://developers.google.com/ml-kit/vision/text-recognition/v2/ios)、[顔検出](https://developers.google.com/ml-kit/vision/face-detection/ios)

## 過去に比較した拡張候補（今回の採用対象外）

2026-11-07にクリエイティブカテゴリで進める方針が決定しました。以下は教育を検討した時点の比較メモで、今回の追加作業には含めません。既存MVPの制作・公開支援と効果検証を優先します。

教育の方向を選び、「なぜ公開に注意が必要か」を根拠とともに学ぶ機能が中核になる場合は、**EmbeddingGemma 2による端末内検索**を比較候補にできます。一般的なSNSガイドや教材の関連箇所を取り出し、Gemmaの説明に参照させる構想です。機密の投稿内容を検索サーバーへ送らずに済む設計を目指します。

GoogleはEmbeddingGemma 2を利用した端末内の意味検索を案内しています。ただし本アプリへのFlutter連携・モデル容量・メモリ・起動時間は未検証です。現行の `litertlm` バージョンでそのまま利用できると断定せず、技術検証後に採否を決めます。[Semantic Retriever公式資料](https://developers.google.com/edge/mediapipe/solutions/retrieval/semantic_retriever)

今のMVPは既存の静止画チェックと修正・書き出しの検証を先に行います。ライブの追加案は維持します。EmbeddingGemma 2は未採用でP0には追加しません。

## 審査に向けた説明

> 投稿内容をクラウドへ渡したくないため、Gemma 4 E2BをLiteRT-LMでiPhone内実行する。撮影中はML Kitで文字や顔の写り込みに気づかせ、撮影後は写真と文章を合わせて確認する。位置の特定はML Kit、文脈の補助はGemmaに分担し、公開の判断は利用者に残す。

撮影中警告は追加予定なので、現時点の説明ではその旨を付記します。SDKの診断通信まで含めた通信ゼロはうたいません。

保存した[大会ルール](../hackathon-rules.md)では、珍しい技術を使うだけの加点は明記されていません。中核への有効性と合理的な選定理由が評価対象です。指定Google Cloud実行基盤の条件は未対応であり、Cloud Run等の配布用途で満たせるかも未確定です。
