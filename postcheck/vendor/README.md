# iOS依存管理の互換パッチ

Firebase Core 4.15.2 / Auth 6.7.1 / google_sign_in_ios 6.3.8 の公開パッケージ。出典・バージョンはprovenance.json。ライセンスは各ディレクトリに保持。

現行の日本語ML KitはCocoaPods、LiteRT-LMはSwiftPMのみのため両方が必要。Firebase/GoogleSignInをSwiftPMからリンクすると、ML KitのPods側にもあるFBLPromises等が二重リンクされる。これら3ブリッジのPackage.swiftだけをPackage.swift.disabledにリネームし、Flutter標準のCocoaPodsフォールバックでGoogle SDK群をひとつの依存グラフに統合する。プラグイン実装コードは変更していない。サンプル・テスト・生成キャッシュはコピー対象外。

pubspecのdependency_overridesでローカルの互換パッチを参照する。ユーザー共通pub-cacheを変更しない。Firebase 5.xのiOS13系SDKは現在のFlutter対応GoogleSignIn 9.xとGTM Session Fetcherの要件が競合したため4.15.2/6.7.1に固定。Flutterや日本語ML Kitを更新するときに、この互換パッチの必要性を再確認する。

## camera_avfoundation 0.11.1：内カメラの向き

2026-11-08追加。このパッケージはSwiftPMを維持し、`DefaultCamera.updateOrientation`の接続設定だけを変更する。iPhone 17 Proの内カメラが横向きのままになるという実機報告への対応。上流のiOS 17以上の分岐は縦向きを固定90度に変換していたが、iPhone 17世代の前面センサーは取り付け方向が異なる。[Appleの説明](https://developer.apple.com/videos/play/wwdc2026/341/)、[Apple技術者の補足](https://developer.apple.com/forums/thread/825928)。

互換パッチではAVFoundationの`videoOrientation`へ縦・横の意味を渡し、機種ごとの回転処理をOSへ委ねる。映像出力と写真出力の両方へ適用するため、Flutterの表示だけを90度回転させる補正は追加しない。`videoOrientation`はiOS 17から非推奨だが現在のSDKで利用できる。固定した撮影方向を守るための暫定対応とし、上流にセンサー方向と撮影方向ロックを両立する実装が入ったら置き換える。Dart・ライセンス・SwiftPM manifestは上流のまま。上流のSwiftテストも保持しているが、このプロジェクトのFlutterテスト実行には含まれない。
