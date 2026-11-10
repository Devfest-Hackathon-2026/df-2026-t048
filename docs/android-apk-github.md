# Androidのキー・署名・APK作成

## Googleマップのキー

Maps SDK for Androidを有効にしたGoogle CloudプロジェクトでAndroid用APIキーを作成します。キーのAPI制限はMaps SDK for Android、アプリ制限はパッケージ名 `jp.kawakou.postcheck` と実際にAPKを署名する証明書のSHA-1です。GitHubで直接配布するAPKには、そのAPKの署名証明書を登録します。

ビルドするPCの `~/.gradle/gradle.properties`（Windowsでは通常 `C:\Users\ユーザー名\.gradle\gradle.properties`）に保存します。

```properties
POSTCHECK_MAPS_API_KEY=取得したAndroid用キー
```

または環境変数 `ORG_GRADLE_PROJECT_POSTCHECK_MAPS_API_KEY` にキーを設定します。単に `POSTCHECK_MAPS_API_KEY` という環境変数を設定したり、`.env` を置いたりしても現在のGradle設定では読み込みません。キーはGitへコミットしません。

## 配布用署名

既存の署名鍵を使い、Git対象外のファイルに次を設定します。値は例示用のプレースホルダーです。

```properties
storeFile=/absolute/path/to/release.jks
storePassword=端末内で設定
keyAlias=署名鍵のエイリアス
keyPassword=端末内で設定
```

このファイルのパスを環境変数 `POSTCHECK_ANDROID_KEY_PROPERTIES` で指定します。未指定時はMacの `~/Library/Application Support/PostCheck/android-signing/key.properties` を参照します。既存配布版と署名が異なると上書き更新できないため、同じ鍵を安全に管理します。

## ビルド

FlutterとAndroid SDKを設定し、リポジトリ内の `postcheck/` で実行します。

```sh
flutter pub get
bash scripts/setup_screen_detector.sh
bash scripts/build_android_release_apk.sh 1
```

最後の数字はversionCode。地図ON・公開施設API接続・配布用署名のAPKを、既定では `~/Library/Caches/PostCheckAndroidApk/source/build/app/outputs/flutter-apk/app-release.apk` に出力します。`POSTCHECK_ANDROID_APK_BUILD_ROOT` でビルド領域を変更できます。GitHub Actionsはこの提出用リポジトリでは利用できません。

Gemma本体、ホワイトボード・額縁等の試験モデル、ローカル設定、署名鍵は配布物へ含めません。APKはGitのソースへ追加せず、必要な場合はGitHub Releasesの添付ファイルとして公開します。インストールする人の環境変数設定は不要です。

キーはAPKへ組み込まれ、APKから読み取れるため、Google Cloud側のAPI・アプリ制限が必要です。キー変更後は再ビルドします。

[Google公式のキー設定](https://developers.google.com/maps/documentation/android-sdk/get-api-key)。
