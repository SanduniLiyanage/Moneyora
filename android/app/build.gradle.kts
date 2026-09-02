plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.moneyora.moneyora"
    // Back to Flutter's default (36), after compileSdk = 37 turned out not to
    // work. API 37 ships as "37.0" - Android now uses decimal API levels - and
    // AGP 9.1.0 cannot resolve them: Gradle installs platforms/android-37.0
    // and then fails looking for a target named android-37.
    //
    // AGP 9.1.0 warned that 36 was its maximum recommended compileSdk when 37
    // was set. That warning was correct and worth having believed.
    //
    // The only thing that wanted 37 was flutter_secure_storage 11, now pinned
    // to 10.3.1. Revisit when the Flutter toolchain ships an AGP that
    // understands decimal API levels.
    compileSdk = flutter.compileSdkVersion
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
