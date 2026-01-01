plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.github.festeh.bro"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.github.festeh.bro"
        // Wear OS 2.0+ requires minSdk 25
        minSdk = 25
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // VAD - WebRTC (default, 158KB, battery efficient)
    implementation("com.github.gkonovalov.android-vad:webrtc:2.0.10")
    // Opus encoding/decoding - theeasiestway/android-opus-codec
    implementation(project(":opus"))
    // Wear DataLayer API for phone sync
    implementation("com.google.android.gms:play-services-wearable:18.2.0")
    // Coroutines for Play Services Tasks
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.7.3")
}
