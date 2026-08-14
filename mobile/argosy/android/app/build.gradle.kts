import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is driven by android/key.properties (gitignored), populated
// locally or by mobile-release.yml from CI secrets. When it's absent we fall
// back to the debug key so `flutter run --release` and CI debug builds still work.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "dev.dodson.argosy"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        // AGP 9 defaults this off; the launcher label is generated per build
        // type so the dev install is distinguishable (ARGY-202).
        resValues = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.dodson.argosy"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Launcher label, so the debug variant can override it below. Defined
        // as a resValue rather than in strings.xml because a build type can
        // replace this, but cannot replace a resource file entry.
        resValue("string", "app_name", "Argosy")
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        debug {
            // Install beside the Play build instead of replacing it (ARGY-202).
            //
            // Sharing one applicationId meant a dev build evicted the app the
            // device actually watches things on, and cost a re-pair either way
            // (`flutter install` drops the token outright). On the verification
            // phone that made every on-device check expensive enough to skip,
            // which is the wrong incentive for the one class of bug CI can't
            // see.
            //
            // A distinct id also means distinct storage, so the dev app keeps
            // its own pairing, stow index and preferences — it can stay pointed
            // at the dev server while the Play build stays on prod, rather than
            // the two fighting over one token.
            //
            // Debug-only: `flutter build apk/appbundle --release` keeps the
            // original id, so mobile-release.yml's `packageName` stays correct.
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            resValue("string", "app_name", "Argosy Dev")
        }
        release {
            // Sign with the upload key when key.properties is present (CI tags /
            // local release builds); otherwise the debug key so dev still works.
            signingConfig = signingConfigs.getByName(
                if (hasReleaseSigning) "release" else "debug",
            )
            // AGP 9 flipped isMinifyEnabled to default-true for release. R8 then
            // shrinks/obfuscates reflection-driven startup deps pulled in
            // transitively by flutter_secure_storage (androidx.startup →
            // WorkManager's WorkDatabase_Impl, Google Tink), so the release APK
            // crashes on launch with "Unable to get provider
            // androidx.startup.InitializationProvider" (ARGY-114). We don't need
            // code/resource shrinking for a self-hosted client, so opt out
            // explicitly. To re-enable shrinking later, flip both back on and add
            // keep rules for androidx.work.**, androidx.startup.**,
            // com.google.crypto.tink.**.
            isMinifyEnabled = false
            isShrinkResources = false
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
