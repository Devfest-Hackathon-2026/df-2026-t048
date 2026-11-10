# 施設ごとの物体検出モデル：作成手順（最初の対象：ホワイトボード）

作成：2026-11-09。範囲は**モデルの学習・変換・互換性確認**まで。アプリのiOS／Android統合、画面、モデル配布は変更していない（Androidは別担当）。

ツール一式：[ml/object_detection/](../ml/object_detection/)。

## 1. 結論

- **TFLite Model Maker 0.4.3＋EfficientDet-Lite0** で学習し、TFLite（int8、DetectionPostProcess込み、ObjectDetector metadata付き）として書き出す。
- 理由：現行iOS検出器（TensorFlowLiteTaskVision 0.4.3の`ObjectDetector`）は **出力4個のDetectionPostProcessモデル**しか読めない。この形式で書き出せるGoogle公式の学習ツールは、候補の中でTFLite Model Makerだけだった。現行モデルと同じEfficientDet-Lite0系統・320×320・uint8入力で揃えられる。
- MediaPipe Model Makerは**出力2個（NMSなし）**で書き出すため、現行iOS検出器では読めない。公式のMediaPipe版EfficientDet-Lite0で実際に確認した（§7）。
- 最大のリスクは保守。TFLite Model Makerの最終リリースは2024-01、Python 3.9／TensorFlow 2.8に固定される。そのため、版を固定したlinux/amd64コンテナに閉じ込めた。

## 2. 現行アプリの要件（コードの根拠）

| 項目 | 現状 | 根拠 |
| --- | --- | --- |
| 実行ライブラリ | TensorFlowLiteTaskVision 0.4.3（CocoaPods） | [Podfile](../postcheck/ios/Podfile) |
| 検出器設定 | `scoreThreshold 0.35`、`maxResults 10`、`labelAllowList ["laptop","cell phone","tv"]` | [AppDelegate.swift:147-151](../postcheck/ios/Runner/AppDelegate.swift#L147-L151) |
| モデル配置 | `assets/screen_detector/efficientdet_lite0.tflite`（固定パス、Git対象外、SHA-256照合） | [setup_screen_detector.sh](../postcheck/scripts/setup_screen_detector.sh) |
| Flutterへの受け渡し | `[x,y,w,h]`（＋任意で四隅8値）のみ。**ラベル・スコアは返さない** | [screen_device_detector.dart](../postcheck/lib/adapters/screen_device_detector.dart) |
| 現行モデル | 入力 `[1,320,320,3]` uint8。出力4個：locations `[1,25,4]`、classes `[1,25]`、scores `[1,25]`、count `[1]`。COCO 90ラベル | §7で実測 |

Task Library公式の互換要件（[ObjectDetector](https://ai.google.dev/edge/litert/inference_with_metadata/task_library/object_detector)）：
- 入力1個、`[1,H,W,3]`、uint8またはfloat32（float32ならNormalizationOptionsが必須）
- 出力は`DetectionPostProcess`の4個（locations／classes／scores／検出数）
- locationsに`BoundingBoxProperties type=BOUNDARIES`が必要
- ラベルは`TENSOR_VALUE_LABELS`の関連ファイル（metadataへ同梱）

### 統合担当者への注意（今回は未変更）

- **ラベル許可リスト**：`whiteboard`だけのモデルを今の設定（`laptop, cell phone, tv`）で読み込むと、一致するラベルがないためTask Libraryが**読み込み時にエラー**を返す（§7、Python版で確認）。`verify_model.py --allow`で事前に検出できる。
- **ラベルが返らない**：現在の受け渡しは矩形だけのため、ホワイトボードと画面機器を区別できない。施設ごとに出し分けるには、ラベルの受け渡しが要る。
- **ひとつのモデルにする場合**：カスタムモデルの学習時は、クラスを`labels.txt`に書いたものだけに置き換える。COCOの`laptop`／`cell phone`／`tv`は引き継がれない。現行の画面機器検出も1モデルにまとめるなら、それらのクラスも自前で注釈して同時に学習する。もう一つの選択肢は、2モデルの併用。
- Android：Task Library（`tensorflow-lite-task-vision`）なら同じ形式のはず。MediaPipe Tasks Androidで読めるかは**未検証**。

## 3. 候補ツールの比較

| | TFLite Model Maker | MediaPipe Model Maker |
| --- | --- | --- |
| 版・最終リリース | 0.4.3（2024-01-23） | 0.2.1.4（2024-04-22） |
| ライセンス | Apache-2.0 | Apache-2.0 |
| 主な依存 | `scann==1.2.6`（TF 2.8固定）、`numpy<1.23.4`、`tf-models-official==2.3.0` | `tensorflow>=2.10,<2.16`、`tf-models-official>=2.13.2,<2.16` |
| モデル | EfficientDet-Lite0〜4 | MobileNetV2-SSD、MobileNet-MultiHW-AVG |
| 書き出し | `post_mode='tflite'`（NMS込み、出力4個）＋`MetadataWriter.create_for_inference` | `create_for_models_without_nms`（**出力2個**、アンカーはmetadata） |
| 現行iOS（Task Library 0.4.3） | **読める**（§7で実証） | **読めない**（§7でエラー再現） |

根拠のソース：[TFLite Model Maker object_detector.py](https://github.com/tensorflow/examples/blob/master/tensorflow_examples/lite/model_maker/core/task/object_detector.py)、[object_detector_spec.py](https://github.com/tensorflow/examples/blob/master/tensorflow_examples/lite/model_maker/core/task/model_spec/object_detector_spec.py)、[MediaPipe Model Maker object_detector.py](https://github.com/google-ai-edge/mediapipe/blob/master/mediapipe/model_maker/python/vision/object_detector/object_detector.py)、PyPIのメタデータ。

選ばなかった案：
- MediaPipe Model Maker＋iOSをMediaPipe Tasksへ移行：過去に初期化停止とGTMシンボル重複が起きた（[screen-device-detection.md](screen-device-detection.md)）。iOS側の作り直しが必要。
- TensorFlow Object Detection API：DetectionPostProcess付きで書き出せるが、metadataを別途付与する必要があり、手順と依存が増える。
- Ultralytics YOLO等：出力形式が異なり、ライセンスはAGPL-3.0。

## 4. 環境

macOS（Apple Silicon）では`tflite-support`のarm64用wheelがないため、学習も確認も**linux/amd64のDocker**で行う。Apple SiliconではRosettaで動作するため遅い。データが増えたら、x86_64のLinux機での実行を推奨（同じDockerfileを使える）。

```bash
cd ml/object_detection
./od.sh build          # 約1GB。requirements.lock.txtが2026-11-09時点の解決結果
```

Python 3.9はサポート終了済み。コンテナは学習専用とし、外部公開するサービスには使わない。

## 5. データの形式と配置

**画像だけでは学習できない。** 各画像に、ホワイトボードの位置を囲むBounding Boxとクラスラベル（`whiteboard`）が必要。

```
ml/object_detection/data/whiteboard_v1/     ← Git対象外
  images/IMG_0001.jpg ...
  annotations/IMG_0001.xml ...              ← Pascal VOC。画像と同じファイル名（拡張子違い）
  manifest.csv                              ← 1画像1行
```

- `labels.txt`：1行1クラス。行の順がモデルのクラス番号になる。`background`は予約語。
- `annotations/*.xml`：Pascal VOC。`<size>`は**EXIF回転を適用した後**の幅・高さ。`<object><name>whiteboard</name><bndbox>xmin ymin xmax ymax</bndbox>`はピクセル座標。ホワイトボードのない画像は、XMLを省略するか`<object>`なしで作る。
- `manifest.csv`：列は[manifest.example.csv](../ml/object_detection/manifest.example.csv)を参照。

| 列 | 内容 |
| --- | --- |
| `group_id` | **撮影場所＋撮影機会**（例：`office-a_room-301_2026-11-20`）。同じ部屋・同じ連写・同じ動画からの切り出しは同じIDにする |
| `kind` | `positive`（ホワイトボードあり）／`negative`（なし） |
| `negative_kind` | `white_wall`／`projector_screen`／`window`／`whiteboard_like_paper`／`monitor_off`／`other`／`none` |
| `source`・`license`・`rights_holder`・`consent` | 出所と権利。空欄の行があると`prepare_split.py`がエラーにする |

### Bounding Boxの付け方

- ツール：ローカルで動く[CVAT](https://github.com/cvat-ai/cvat)（MIT）または[Label Studio](https://github.com/HumanSignal/label-studio)（Apache-2.0）。いずれも「Pascal VOC」で書き出せばそのまま使える。COCOで書き出した場合は`coco_to_voc.py`で変換する。**画像を外部のAIアノテーションAPIへ送らない。**
- 枠は、ボードの**書き込み面と枠（フレーム）を含む外接矩形**とする。脚・トレイ・壁は含めない。
- 一部が隠れていても、見えている範囲を囲む。写っている範囲が小さすぎて人も判断できないものは`difficult=1`にする（評価の対象外）。
- 斜めに写っていても、外接する軸平行の矩形を付ける（四隅の推定は、既存のアプリ側の処理の担当）。
- 1枚に複数あれば全部囲む。**囲み漏れがあると、正しく検出しても誤検出として学習・評価される。**

### 集める画像（目安）

- 正例：施設・部屋・照明・距離・角度・書き込みの有無、置き型か壁掛けか、部分的に隠れているか、をばらつかせる。
- 紛らわしい負例：白い壁、プロジェクタースクリーン、窓、掲示物や模造紙、消灯したモニター。学習にも評価にも入れる。
- 1000枚／クラスは現時点の目安で、精度を保証する数ではない。まずは数十〜数百枚で一周回し、`evaluate.py`の誤検出と未検出を見て、追加する画像を決める。

### 公開データ（Open Images）からの取得

2026-11-09に、`fetch_openimages.py`でOpen Imagesから取得した。

**抽出**：2.3GBの注釈CSVは保存せず、ダウンロードしながら`grep`でWhiteboard（`/m/02d9qx`）の行だけを`data/openimages_raw/`へ保存した。

```bash
cd ml/object_detection/data/openimages_raw
B=https://storage.googleapis.com/openimages; M=',/m/02d9qx,'
for s in train:v6/oidv6-train-annotations-bbox.csv validation:v5/validation-annotations-bbox.csv test:v5/test-annotations-bbox.csv; do
  curl -fsSL $B/${s#*:} | grep -F "$M" | sed "s/^/${s%%:*},/"; done > wb_bbox.csv
for s in train:v5/train-annotations-human-imagelabels-boxable.csv validation:v5/validation-annotations-human-imagelabels-boxable.csv test:v5/test-annotations-human-imagelabels-boxable.csv; do
  curl -fsSL $B/${s#*:} | grep -F "$M" | sed "s/^/${s%%:*},/"; done > wb_labels.csv
curl -fsSL $B/v6/oidv6-train-annotations-bbox.csv | head -1 > bbox_header.csv
cd ../.. && python3 fetch_openimages.py --raw data/openimages_raw --out data/openimages_whiteboard_v1
./od.sh split --dataset data/openimages_whiteboard_v1 --out runs/oi_v1/split
```

**取得結果**
- 候補は、枠付きのホワイトボード画像が964枚、「なし」と人が確認済みの画像が902枚。
- CC BY 2.0かつ回転情報のない画像に絞り、**正例956枚・負例500枚、計1456枚（325MB）**を取得した。失敗は0件。
- 負例のうち、窓・モニター・ポスター等が写った紛らわしい画像は122枚。残りは無関係な場面。

**分割**：撮影者（Flickrアカウント）単位で分けた。

| | 画像 | 正例 | 負例 | 枠 |
| --- | ---: | ---: | ---: | ---: |
| 学習 | 1018 | 674 | 344 | 759 |
| 検証 | 219 | 137 | 82 | 152 |
| 評価（学習に使わない） | 219 | 145 | 74 | 150 |

**目視確認で分かったこと**（評価用の正例から12枚を抽出）
- 枠の位置は合っていた。
- ただしOpen Imagesの「Whiteboard」には、**投影中のスクリーンや電子黒板の画面**、ホワイトボードに見えない紙が含まれていた（12枚中3枚）。プロジェクタースクリーンを負例とする本プロジェクトの方針とは食い違う。学習前に正例を目視で確認し、方針に合わない画像を除くか`difficult`にすることを推奨する。
- 分割をまたぐ類似画像の警告は296組あった。6組を見た限りでは、白っぽい画像どうしの誤判定で、同じ写真の漏れは見つからなかった。

**目視レビューによる除外**（2026-11-09）

全1456枚を16枚ずつの番号付き一覧画像にし、Claudeが目視で確認した。迷ったものは除外する基準とした。除外リストは`data/openimages_whiteboard_v1/review_exclusions.csv`。1枚分は、担当者が同じ判断になることを再確認した。

| 対象 | 除外 | 内訳 |
| --- | ---: | --- |
| 正例956枚 | 242 | 紙（フリップチャート・模造紙・ポスター等）134、投影（スクリーン・電子黒板の投影）54、判別不能・ボード以外43、壁・看板10、黒板1 |
| 負例500枚 | 59 | ホワイトボードが写っている28、判別不能31 |

除外後の分割は次のとおり（`./od.sh split ... --exclude data/openimages_whiteboard_v1/review_exclusions.csv --out runs/oi_v1_reviewed/split`）。

| | 画像 | 正例 | 負例 | 枠 |
| --- | ---: | ---: | ---: | ---: |
| 学習 | 805 | 500 | 305 | 548 |
| 検証 | 176 | 104 | 72 | 113 |
| 評価（学習に使わない） | 174 | 110 | 64 | 113 |

注意点
- 「迷ったら除外」としたため、本物のホワイトボードも一部除外されている。文字の接写、紙が多く貼られたボード、グラフィックレコーディングなど。
- 判定はAIによる目視で、人の最終確認はしていない。

**ライセンス**
- 画像：CC BY 2.0（`manifest.csv`に作者とFlickrのURLを記録）
- 注釈：CC BY 4.0（Google）
- モデルや資料で使う場合は、作者の表記が必要。

### 合成データ（実写の代わりの仮データ）

`./od.sh synth --out data/synth_whiteboard_v1` で、端末内でプログラム的に描いた画像を生成する。外部の画像生成AIは使わない。既定は325枚で、内訳は次のとおり。

- 正例200枚：40部屋×5ショット。ホワイトボードと枠付き
- 負例125枚：25部屋×5ショット。白い壁、プロジェクタースクリーン、窓、模造紙、消灯モニター

`./od.sh split` で、部屋単位に学習225／検証50／評価50枚へ分ける。評価の50枚は学習に使わない。

- 枠は描いた位置から計算するため正確。ただし、見た目は単純な図形で、実写とは大きく違う。**合成データでの成績は、実写での精度を示さない。** 実写を集めるまでの仕組み確認と、学習の補助に使う。
- 異なる部屋どうしの単調な壁が、類似画像の検査で数十組引っかかる。見た目が似ているだけで、同じ撮影の漏れではない。

## 6. 実行手順

```bash
cd ml/object_detection
# 1) 検証と分割（group_id単位。既定は学習70%・検証15%・評価15%）
./od.sh split --dataset data/whiteboard_v1 --out runs/v1/split
# 2) 学習と書き出し（既定：lite0、50 epoch、int8）
./od.sh train --split runs/v1/split --out runs/v1/model
# 3) 互換性検査（アプリと同じ許可リストを指定する）
./od.sh verify runs/v1/model/model.tflite --expect-labels labels.txt --allow whiteboard
# 4) 評価（Task Libraryで推論し、しきい値0.25/0.35/0.5で集計）
./od.sh evaluate --model runs/v1/model/model.tflite --split runs/v1/split --out runs/v1/eval --draw
```

- **分割**：撮影グループごとに、学習・検証・評価のどれか一つへ割り当てる。正例のグループと負例のグループは別々に配分し、各側に負例が入るようにする。グループIDの付け忘れに備え、dHashで分割をまたぐ類似画像も検出し、`split_report.json`に記録する。画像はEXIF回転を適用して再保存し、**GPS等のメタデータを除去**する。
- **学習**：`--train-whole-model`はデータが増えてから使う。`train_config.json`に、版・設定・SHA-256・画像数を記録する。
- **評価**：画像ごとに`success`／`true_negative`／`false_positive`／`missed`へ分類し、`per_image.csv`へ出力する。負例の誤検出は`negative_kind`別に数える。`--draw`を付けると、分類別のフォルダへ確認用の画像を出す（緑＝正解、赤＝検出）。正解枠または負例画像が`--min-count`（既定100）未満のときは、比率を**参考値**と明示する。
- Model Makerの`evaluate_tflite`によるCOCO指標（`eval_model_maker.json`）も出す。ただし、アプリと同じ経路の評価は`evaluate.py`のほう。

## 7. 検証結果（2026-11-09、この環境で実行）

ホワイトボードの画像はまだないため、**仕組みの確認だけ**を行った。以下の数値は、ホワイトボードの性能を示さない。

**環境**：`./od.sh build`が成功（Apple Silicon上のDocker linux/amd64、所要約7分、`pip check`で不整合なし）。

**互換性検査の判定確認**（`verify_model.py`）

| モデル | 結果 |
| --- | --- |
| 現行アプリのモデル（SHA-256 `2e04c53b…`、アプリの固定値と一致） | 全項目OK。入力`[1,320,320,3]` uint8、出力4個、BOUNDARIES、ラベル90個。Task Libraryで読み込み・推論できた |
| MediaPipe公式のEfficientDet-Lite0 int8 | NG。出力2個（`[1,19206,4]`、`[1,19206,90]`）、DetectionPostProcessなし。Task Libraryのエラーは `Mobile SSD models are expected to have exactly 4 outputs, found 2`（過去にアプリで起きた不具合と同じ原因） |

**学習から評価までの通し確認**：Google公式MediaPipeチュートリアルの`android_figurine`（72枚、2クラス、COCO形式）を使用。画像は作業用の一時ディレクトリだけに置き、リポジトリへは入れていない。ライセンス表記は確認できていないため、動作確認以外には使わない。

1. `coco_to_voc.py`で変換 → `prepare_split.py`で学習50／検証11／評価11へ分割。負例がないことを警告できた。
2. `train.py`（lite0、10 epoch、batch 8、int8）が約2分で完了。出力は4.4MB。
3. `verify_model.py`は全項目OK（入力uint8 `[1,320,320,3]`、出力4個、BOUNDARIES、同梱ラベル`android, pig_android`）。Task Libraryで読み込み・推論できた。
4. **現行アプリの許可リスト`laptop, cell phone, tv`を指定すると、Task Libraryがモデル読み込みの時点でエラーになる**（`Invalid class names specified via class_name_whitelist: none match with model labels.`）。iOSでも同じ実装なら、検出器の初期化に失敗する（iOS実機は未確認）。
5. `evaluate.py`（評価11枚・正解枠13個、しきい値0.35）：成功2、誤検出5、未検出4。件数が少ないため、比率は参考値として出力した。確認用画像で、検出枠と正解枠の座標系が一致していることを目視で確認した。
6. 負例：写真の中で物体と重ならない領域を切り出した12枚を負例として追加した。`<object>`なしのVOCを含めても学習（1 epoch）が止まらず、評価で`true_negative`として数えられた。

その他の観察：検出枠が画像の外へはみ出すことがある（例：x=-33）。アプリ側で範囲を切り詰める処理が必要かは、統合時に確認する。

## 8. ライセンス・保存場所

| 対象 | ライセンス・扱い | 保存場所 |
| --- | --- | --- |
| TFLite Model Maker / tflite-support / TensorFlow | Apache-2.0（PyPI） | Dockerイメージ（ローカル） |
| 事前学習済みバックボーン（`train_config.json`の`pretrained_backbone`） | **未確認**。automlのREADMEに記載なし。配布前にKaggle Models（旧TF Hub）のページで確認する | `runs/.tfhub_cache`（Git対象外） |
| 学習画像・注釈 | 撮影者・施設の許諾に従う。`manifest.csv`に出所・権利・同意を記録 | `ml/object_detection/data/`（Git対象外）。チーム共有は権限を限定した保管場所で |
| 学習済みモデル | 上記の条件を引き継ぐ | `runs/`（Git対象外）。アプリへ入れる際は、既存モデルと同じくSHA-256で固定する |

- 人が写る画像や施設の機密（ホワイトボードの書き込み内容）は、許諾範囲を確認してから使う。共有前に、書き込みの映り込みも確認する。
- `.gitignore`で`data/`、`runs/`、`*.tflite`、`*.tfrecord`、`*.ckpt*`を除外している。

## 9. 未確認事項

- 実際のホワイトボード画像はまだ用意していないため、**ホワイトボードの学習・精度評価は未実施**。
- iOSのTaskVision 0.4.3で、カスタムモデルを読み込めるかの実機確認。今回の確認はPython版Task Library 0.4.4による。
- Android（Task LibraryまたはMediaPipe Tasks）での読み込み。
- 端末での推論速度・電池消費。lite1／lite2を使う場合の速度。
- 事前学習済み重みのライセンス表記。

## 10. アプリへの試験組み込み（2026-11-09、ユーザー指示）

- iOS（[AppDelegate.swift](../postcheck/ios/Runner/AppDelegate.swift)）とAndroid（[PostCheckDeviceDetector.kt](../postcheck/android/app/src/main/kotlin/jp/kawakou/postcheck/PostCheckDeviceDetector.kt)）で、既存のEfficientDet-Lite0（laptop / cell phone / tv）とホワイトボード用モデル（whiteboard）を並列に読み込み、写真ごとに両方の結果をまとめて返す。どちらかが読めなくても、もう一方は動く。
- ホワイトボード用モデル `postcheck/assets/screen_detector/whiteboard_experiment.tflite` は、ユーザー承認の例外としてGitに含めた。中身は200枚・20 epochの試験学習。SHA-256は`fe195f55…`。**配布不可**。
- 制約
  - Flutterへはラベルを渡していないため、表示名は「パソコン・スマホ」のまま。
  - Androidのライブ検出は、その後のユーザー指示で有効化した（`live_camera_page.dart`）。
    - NV21フレームをsensorOrientationで正立させ、インカメラは左右反転する。
    - ネイティブ側はNV21→JPEG→Bitmap→回転してから検出する。
    - Xperiaの背面カメラで、利用者が「いいかんじ」と確認した。
    - インカメラ・速度・発熱は未計測。
  - 施設ごとの出し分けはまだない。
- 確認状況
  - iOS：署名なしでのビルドが通った（`main`取り込み前のコード）。
  - Android：profileビルドをXperiaにインストール済み。実際の検出表示は利用者の撮影で確認中。
  - Androidのreleaseビルドは、`main`の時点から別の理由で失敗している（R8でML KitのOCR言語クラスが不足）。
