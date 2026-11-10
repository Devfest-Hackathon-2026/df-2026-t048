# パソコン・スマホの検出：実装と実機検証

更新：2026-11-08、撮影後の四隅候補と多角形・ブラシ編集を追加。以下の矩形のみの記述は初期実装の記録です。現在の動作と検証範囲は [輪郭マスク編集](freeform-mask-editor.md) を参照。

2026-11-08。対象は iPhone 17 Pro / iOS 27.0.1。

## 現行構成

- iOS: TensorFlowLiteTaskVision 0.4.3。Flutter の MethodChannel を介して端末内で実行。
- モデル: Google EfficientDet-Lite0、Task Library 用の検出後処理・メタデータ付き版。出力が4個のモデルを使用する。
- 対象ラベル: `laptop`、`cell phone`、`tv`。しきい値0.35、最大10件。
- 撮影中は既存の750ms間隔・同時処理1件の制限内で検出。2秒以上古い枠は表示しない。
- 撮影後は確認候補として提示し、利用者がぼかし／黒塗りを選ぶ。機器全体の矩形であり、画面の四隅を推定する機能ではない。
- 入力・結果をクラウドへ送信しない。写真用の一時ファイルは既存の解析処理で削除する。
- ネイティブ呼び出しは4秒でタイムアウト。ライブ機器検出の失敗を表示し、以降の文字・顔認識を継続する。撮影後も失敗を注記する。

## Android（2026-11-09追加・実機未検証）

- 撮影後の写真だけを対象に、`postcheck/screen_detector` の `file` を Android でも受ける（`postcheck/android/.../PostCheckDeviceDetector.kt`）。撮影中のライブ検出は、Androidのカメラ映像の向き・形式が未検証のため引き続き無効。
- 実行は MediaPipe Tasks Vision 0.10.26.1 の `ObjectDetector`。モデル・対象ラベル・しきい値・最大件数は iOS と同じ（同梱の EfficientDet-Lite0 をメモリへ読み込む）。
- TFLite Task Library（`tensorflow-lite-task-vision` 0.4.4）も試したが、ネイティブライブラリが4KB境界で、Android 15以降で求められる16KBページサイズに対応していなかったため採用しない。MediaPipe版のAPKでは、全ネイティブライブラリが16KB以上の境界であることを `llvm-readelf` で確認した。
- iOS は Vision の矩形検出で四隅候補を付けるが、Android は検出器の矩形だけを返す。
- 確認したこと：`./gradlew assembleDebug` が成功し、APKにモデルと MediaPipe のライブラリが入ること。Mac上の MediaPipe（Python）で同じモデルを同じ条件で読み込めること、合成画像で座標が左上原点のピクセル値で返ることを確認した。
- 未確認：Android実機での初期化・検出・速度。iOSでは MediaPipeTasksVision 0.10.21 の初期化が戻らない事例があったため（下記）、Android実機での確認が必要。

## 「枠が出ない」の調査で確認した事実

最初に組み込んだ MediaPipeTasksVision 0.10.21 は実機で `ObjectDetector` 初期化から戻らなかった。0.10.35 / 1.0.0 は既存Google SDKとのGTM関連シンボル重複でビルドできなかった。初期化停止の内部原因までは確定していない。

TensorFlowLiteTaskVisionへ切り替えると初期化処理から応答するようになった。最初のMediaPipe用モデルは出力が2個で、Task Libraryが要求する4個と不一致だったため、対応する公式モデルへ変更した。

TaskVision 0.4.3には既存MLImageと同じ`GMLImage`クラスも含まれる。`ios/deduplicate_taskvision.rb`で、TaskVisionの静的ライブラリから重複した`GMLImage.o`だけを削除し、ML Kitと同じMLImage実装へリンクする。変換カテゴリは保持。版を固定し、版が変わった場合は再検証を要求する。SDK全体のシンボル重複を無視するリンクフラグは使用しない。

## 実機検証の結果

公開されているノートPCの検証用画像1枚で、iPhone上のネイティブ検出器を実行した。

| 入力経路 | 検出件数 | 処理時間 |
| --- | ---: | ---: |
| 写真ファイル | 1 | 34ms |
| 同じ写真をBGRAピクセルバッファへ変換（カメラと同じ入力形式） | 1 | 94ms |

これは1枚・1回の確認であり、実カメラでの検出率、全処理のフレームレート、消費電力を保証する測定ではない。

修正版の通常ビルドをiPhoneへインストール後、利用者から「枠が出た」と実カメラでの表示確認を得た。枠の厳密な位置・向き・追従精度、今回の機器候補に対する撮影後のぼかし操作は追加確認が残る。

同日の静的解析は問題なし、単体・Widgetテスト57件通過。座標の正規化・範囲外の除外・ネイティブ無応答時のタイムアウトを含む。

写真・テスト画像はリポジトリへ追加しない。任意の非機密テスト画像を`postcheck/assets/screen_detector/diagnostic.jpg`へ置き、`POSTCHECK_SELF_TEST=true`と`POSTCHECK_DEVICE_DETECTOR_TEST=true`の専用ビルドで写真/BGRAの2経路を検証できる。結果はアプリの`Documents/postcheck-detector-diagnostic.json`。通常配布前にテスト画像をソースとビルドステージから削除し、フラグを付けずにビルドする。

## モデルの準備

`bash postcheck/scripts/setup_screen_detector.sh`で取得・SHA-256照合を行う。モデル本体はGit対象外。

- [Googleのモデル取得スクリプト](https://github.com/tensorflow/examples/blob/master/lite/examples/object_detection/raspberry_pi/setup.sh)
- [GoogleのiOS ObjectDetector API](https://github.com/tensorflow/tflite-support/blob/master/tensorflow_lite_support/ios/task/vision/sources/TFLObjectDetector.h)

SHA-256: `2e04c53bfeac0ac2a30c057c7e2a777594ce39baaac35a92f74fb1e8c4fc4e0b`
