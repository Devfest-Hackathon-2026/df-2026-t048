# 物体検出モデルの学習ツール

施設ごとの物体（最初はホワイトボード）を検出するモデルを、学習・変換・互換性確認するためのツールです。
方式の選定理由、データ形式、検証結果は [docs/custom-object-detection.md](../../docs/custom-object-detection.md) を参照してください。

| ファイル | 役割 |
| --- | --- |
| `Dockerfile` / `requirements.txt` / `requirements.lock.txt` | 学習・確認環境（linux/amd64、Python 3.9、TFLite Model Maker 0.4.3） |
| `od.sh` | コンテナ内で各手順を実行するラッパー |
| `labels.txt` | クラス名（1行1クラス）。現在は `whiteboard` |
| `manifest.example.csv` | 画像ごとの撮影グループ・出所・権利の記録例（架空） |
| `fetch_openimages.py` | Open Imagesから、枠付きホワイトボード画像と確認済みの負例を取得し、VOCとmanifestを作成（手順は docs 参照） |
| `synth_whiteboard.py` | 合成データの生成（ホワイトボードあり＋枠、紛らわしい負例）。仕組みの確認用で、実写の精度は示さない |
| `contact_sheet.py` | ラベル確認用の番号付き一覧画像と、評価結果の一覧画像を作成 |
| `apply_review.py` | 確認結果（JSON）を除外リスト（`review_exclusions.csv`）にまとめる |
| `coco_to_voc.py` | CVAT／Label StudioのCOCO出力をPascal VOCへ変換 |
| `prepare_split.py` | データ検証、撮影グループ単位の学習／検証／評価分割、EXIF除去 |
| `train.py` | EfficientDet-Liteの学習とTFLite書き出し（DetectionPostProcess＋metadata付き） |
| `verify_model.py` | TFLite Task Library ObjectDetector互換性の検査 |
| `evaluate.py` | 変換後モデルを成功／誤検出／未検出に分けて評価 |

```bash
cd ml/object_detection
./od.sh build
./od.sh synth    --out data/synth_whiteboard_v1      # 実写がまだない場合の合成データ
./od.sh split    --dataset data/whiteboard_v1 --out runs/v1/split
./od.sh train    --split runs/v1/split --out runs/v1/model
./od.sh verify   runs/v1/model/model.tflite --expect-labels labels.txt --allow whiteboard
./od.sh evaluate --model runs/v1/model/model.tflite --split runs/v1/split --out runs/v1/eval --draw
```

`data/`、`runs/`、`*.tflite` はGit対象外です。画像・重み・チェックポイントをコミットしないでください。
