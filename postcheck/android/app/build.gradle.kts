import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Signing material stays outside the repository. Development builds can still
// use the debug key; the internal-test packaging script requires this file.
val uploadPropertiesFile = file(
    System.getenv("POSTCHECK_ANDROID_KEY_PROPERTIES") ?: rootProject.file("key.properties").path,
)
val uploadProperties = Properties().apply {
    if (uploadPropertiesFile.isFile) uploadPropertiesFile.inputStream().use { load(it) }
}

android {
    namespace = "jp.kawakou.postcheck"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "jp.kawakou.postcheck"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["postcheckMapsApiKey"] = project.findProperty("POSTCHECK_MAPS_API_KEY")?.toString() ?: ""
    }

    signingConfigs {
        if (uploadPropertiesFile.isFile) {
            create("upload") {
                storeFile = file(requireNotNull(uploadProperties.getProperty("storeFile")))
                storePassword = requireNotNull(uploadProperties.getProperty("storePassword"))
                keyAlias = requireNotNull(uploadProperties.getProperty("keyAlias"))
                keyPassword = requireNotNull(uploadProperties.getProperty("keyPassword"))
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(
                if (uploadPropertiesFile.isFile) "upload" else "debug",
            )
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.google.mlkit:text-recognition-japanese:16.0.1")
    // Device detection with the same EfficientDet-Lite0 model as iOS.
    // MediaPipe Tasks ships 16 KB page-aligned native libraries.
    implementation("com.google.mediapipe:tasks-vision:0.10.26.1")
}
