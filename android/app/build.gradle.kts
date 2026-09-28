import java.util.Properties

// The Play upload key, read from android/key.properties when it exists.
// Neither that file nor the keystore it names is ever committed (both are
// in .gitignore); docs/SETUP.md says how to make them. Without it a release
// build is signed with the debug key, which installs and runs but cannot be
// uploaded to the Play Console.
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasUploadKey = keyProperties.getProperty("storeFile") != null

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

    signingConfigs {
        if (hasUploadKey) {
            create("upload") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                signingConfigs.getByName(if (hasUploadKey) "upload" else "debug")

            // R8 already ran on release builds - the Flutter Gradle plugin turns
            // minification on - but no project rules file was ever wired in, so
            // it had nothing to consult and the build failed on ML Kit's
            // unresolvable script references. Stated explicitly here rather than
            // left inherited, because "the minifier runs" is exactly the fact
            // that was not obvious when the release build was broken and every
            // CI check was green. See E-09 in docs/SPEC_ERRATA.md.
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
