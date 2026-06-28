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

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.dodson.argosy"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
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
