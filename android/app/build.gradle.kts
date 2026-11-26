import java.util.Properties
import java.io.FileInputStream
import java.util.Base64

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 正式签名信息（不提交到仓库）：android/key.properties
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// flutter build 的 --dart-define 以 Base64 逗号分隔传给 Gradle；PLAY_STORE=true 表示 Google Play 版
val playStoreBuild = (project.findProperty("dart-defines") as String?)
    ?.split(",")
    ?.any { String(Base64.getDecoder().decode(it)) == "PLAY_STORE=true" }
    ?: false

android {
    namespace = "com.gnayoah.wearbox"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.gnayoah.wearbox"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // 只打包了 arm64 版 adb / fastboot
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    // adb / fastboot 以 lib*.so 形式放在 jniLibs 中，安装时需解压到 nativeLibraryDir 才能执行
    packaging {
        jniLibs {
            useLegacyPackaging = true
            // 自带的 adb / fastboot 只有 arm64 版本，排除插件带入的其他架构，
            // 否则商店会把应用分发到无法运行的 32 位 / x86 设备
            excludes += listOf("lib/armeabi-v7a/**", "lib/armeabi/**", "lib/x86/**", "lib/x86_64/**")
            // Google Play 版使用进程内 Dart ADB，不打包 adb / fastboot 可执行文件
            // （其未按 16 KB 页对齐，Play 拒绝发布）
            if (playStoreBuild) {
                excludes += listOf("**/libadb.so", "**/libfastboot.so")
            }
        }
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // 有 key.properties 时使用正式签名，否则回退到 debug 签名（便于他人本地构建）
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
