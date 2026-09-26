import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing (docs/release.md): android/key.properties locally, or the ANDROID_*
// environment variables in CI. Neither file nor secrets are ever committed.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) FileInputStream(file).use { load(it) }
}

fun signingValue(property: String, environment: String): String? =
    keystoreProperties.getProperty(property) ?: System.getenv(environment)

val releaseStoreFile = signingValue("storeFile", "ANDROID_KEYSTORE_PATH")

// The host whose https://<host>/join/<code> invite links open the app (App Links). Set it
// with -PappLinkHost=... or APP_LINK_HOST; the backend serves the matching
// /.well-known/assetlinks.json from ANDROID_CERT_SHA256.
val appLinkHost: String =
    (project.findProperty("appLinkHost") as String?)
        ?: System.getenv("APP_LINK_HOST")
        ?: "friends.invalid"

android {
    namespace = "io.github.urdaraluca.friends"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Fixed for good once the app is in a store.
        applicationId = "io.github.urdaraluca.friends"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // From pubspec.yaml's version (name+code).
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appLinkHost"] = appLinkHost
    }

    signingConfigs {
        if (releaseStoreFile != null) {
            create("release") {
                storeFile = file(releaseStoreFile)
                storePassword = signingValue("storePassword", "ANDROID_KEYSTORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "ANDROID_KEY_ALIAS")
                keyPassword = signingValue("keyPassword", "ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (releaseStoreFile != null) {
                signingConfigs.getByName("release")
            } else {
                // No keystore configured: debug keys, so `flutter run --release` still works.
                // Such an APK can't update one signed with the release key.
                logger.warn("Release build signed with DEBUG keys: no key.properties or ANDROID_KEYSTORE_PATH.")
                signingConfigs.getByName("debug")
            }
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
