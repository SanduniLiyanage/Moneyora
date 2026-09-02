plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.moneyora.moneyora"
    // Pinned rather than inherited from flutter.compileSdkVersion (36),
    // because flutter_secure_storage 11 declares an AAR metadata minimum of
    // 37 and Gradle refuses to link below it.
    //
    // compileSdk is not the same knob as targetSdk or minSdk, and only this
    // one moves:
    //   compileSdk - which APIs the code may reference. No device impact.
    //   targetSdk  - which runtime behaviours the app opts in to.
    //   minSdk     - the oldest device that can install it. Still 26 per SRS 2.3.
    //
    // AGP 9.1.0 warns that its maximum *recommended* compileSdk is 36. That is
    // advisory: compiling against a newer SDK is backward compatible, which is
    // the whole reason the three values are separate.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications (>=17): it uses java.time
        // APIs that do not exist below API 26 and must be desugared.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.moneyora.moneyora"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // SRS 2.3 targets Android 8.0+ (API 26). Pinned rather than inherited
        // from flutter.minSdkVersion so a Flutter upgrade cannot silently widen
        // or narrow the supported device range.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
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

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
