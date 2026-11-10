# 著作物利用シート用：端末内の物体検出で使った素材・データ・モデル

作成日：2026-11-10
対象：PostCheck アプリの写り込み検出（パソコン・スマホ、ワイングラス、本、ホワイトボード、額縁、ポスター）と、その学習に使ったもの。
Gemma など他の機能で使った素材は、各機能の資料を参照すること。

各行を著作物利用シートの1行として、そのまま転記できるように書いている（素材名／提供元／ライセンス・規約／利用箇所）。

## A. アプリに含まれるもの（必ず記載）

| 素材名 | 提供元 | ライセンス | 利用箇所 |
| --- | --- | --- | --- |
| EfficientDet-Lite0 物体検出モデル（lite-model_efficientdet_lite0_detection_metadata_1.tflite、COCO 学習済み） | TensorFlow / Google（https://storage.googleapis.com/download.tensorflow.org/models/tflite/task_library/object_detection/rpi/lite-model_efficientdet_lite0_detection_metadata_1.tflite） | Apache License 2.0 | `postcheck/assets/screen_detector/efficientdet_lite0.tflite`。パソコン・スマホ・ワイングラス・本の検出。取得は `postcheck/scripts/setup_screen_detector.sh` |
| ホワイトボード検出モデル（自作、whiteboard_experiment.tflite） | PostCheck チームが EfficientDet-Lite0 を Open Images で追加学習した**改変版** | 元モデル：Apache 2.0（改変した旨をアプリのライセンス画面に表示）。学習データ：Open Images（B） | `postcheck/assets/screen_detector/whiteboard_experiment.tflite`（200枚・20回学習の試験版） |
| 額縁・ポスター検出モデル（自作、docs_experiment.tflite） | PostCheck チームが EfficientDet-Lite0 を Open Images で追加学習した**改変版** | 元モデル：Apache 2.0（改変した旨をアプリのライセンス画面に表示）。学習データ：Open Images（B） | `postcheck/assets/screen_detector/docs_experiment.tflite`（学習 923枚・確認 200枚） |
| TensorFlow Lite Task Library Vision 0.4.3（iOS） | TensorFlow / Google | Apache License 2.0 | iOS アプリで検出モデルを実行（CocoaPods `TensorFlowLiteTaskVision`） |
| MediaPipe Tasks Vision 0.10.26.1（Android） | Google | Apache License 2.0 | Android アプリで検出モデルを実行（`com.google.mediapipe:tasks-vision`） |

## B. 自作モデルの学習に使ったデータ（必ず記載）

アプリに入っている自作モデル2つの学習に使った画像だけを記載する。「学習用」と、学習中の進み具合の確認に使った「確認用」の画像を含み、学習後の精度確認だけに使った画像は含まない。

| 自作モデル | 学習用 | 確認用 | 撮影者一覧 |
| --- | --- | --- | --- |
| ホワイトボード（whiteboard_experiment.tflite） | 200枚 | 50枚 | `ml/object_detection/credits/whiteboard_exp200.csv`（250枚） |
| 額縁・ポスター（docs_experiment.tflite） | 923枚 | 200枚 | `ml/object_detection/credits/frame_poster_docs_whole_v1.csv`（1,123枚） |

| 素材名 | 提供元 | ライセンス | 利用箇所 |
| --- | --- | --- | --- |
| Open Images Dataset V7 の注釈（物体の枠・画像ラベル） | Google LLC（https://storage.googleapis.com/openimages/web/index.html） | CC BY 4.0 | ホワイトボード検出モデルと額縁・ポスター検出モデルの学習。注釈ファイルはリポジトリに含めない |
| Open Images Dataset V7 の画像（Flickr 投稿写真） | 各撮影者（一覧は上記の撮影者一覧） | CC BY 2.0 | 同上。画像はアプリにもリポジトリにも含めない。撮影者と URL は `ml/object_detection/credits/whiteboard_exp200.csv`（250枚）と `ml/object_detection/credits/frame_poster_docs_whole_v1.csv`（1,123枚）に記載。アプリのライセンス画面にも同じ一覧を表示 |

## C. 開発時だけ使ったツール（アプリには含まれない。記載しておくと安全）

| 素材名 | 提供元 | ライセンス | 利用箇所 |
| --- | --- | --- | --- |
| TFLite Model Maker 0.4.3 | TensorFlow / Google | Apache License 2.0 | 自作モデルの学習（`ml/object_detection/`、Docker 内） |

## モデルを差し替えたときの更新手順

1. `ml/object_detection/make_credits.py` で、新しいモデルの学習画像の撮影者一覧を `ml/object_detection/credits/` に作る。
2. `ml/object_detection/make_app_attribution.py` で、アプリのライセンス画面の文面（`postcheck/assets/licenses/open-images-attribution.txt`）を作り直す。
3. この資料の A・B の表を更新する。
