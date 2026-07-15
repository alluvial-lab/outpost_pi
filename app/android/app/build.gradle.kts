import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing — loaded from android/key.properties when present.
// Configuration-only and non-release tasks must remain usable without local
// secrets; release artifact task graphs are rejected below before execution.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.isFile) {
        FileInputStream(keystorePropertiesFile).use(::load)
    }
}
val requiredReleaseSigningProperties =
    listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val missingReleaseSigningProperties =
    requiredReleaseSigningProperties.filter { keystoreProperties.getProperty(it).isNullOrBlank() }
val hasCompleteReleaseSigningProperties = missingReleaseSigningProperties.isEmpty()
val releaseKeystoreFile =
    keystoreProperties
        .getProperty("storeFile")
        ?.takeIf(String::isNotBlank)
        ?.let(rootProject::file)
val releaseSigningConfigurationError =
    when {
        !keystorePropertiesFile.isFile -> "android/key.properties is missing"
        missingReleaseSigningProperties.isNotEmpty() ->
            "android/key.properties is missing or has blank properties: " +
                missingReleaseSigningProperties.joinToString()
        releaseKeystoreFile?.isFile != true -> "the configured release keystore file is missing"
        else -> null
    }
val releaseSigningError =
    "Release APK/AAB tasks require a complete android/key.properties and an existing release keystore. " +
        "Debug signing is only available to debug builds."

android {
    namespace = "dev.kevoun.outpostpi"
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
        applicationId = "dev.kevoun.outpostpi"
        // plan/23 § "Minimum Android version" — the outpost_pi_identity
        // plugin requires API 34 (Block Store + modern biometry), so
        // the app inherits the same floor. Bump intentional, recorded
        // in the plan.
        minSdk = 34
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasCompleteReleaseSigningProperties) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = releaseKeystoreFile
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            if (hasCompleteReleaseSigningProperties) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

// Public release lifecycle tasks plus the AGP packaging/signing tasks that can
// be invoked directly. Rejecting the ready graph runs before any task can emit
// an unsigned or incorrectly signed release artifact.
val releaseArtifactTaskNames =
    setOf("assembleRelease", "bundleRelease", "packageRelease", "packageReleaseBundle", "signReleaseBundle")
gradle.taskGraph.whenReady {
    val producesReleaseArtifact =
        allTasks.any { task -> task.project == project && task.name in releaseArtifactTaskNames }
    if (producesReleaseArtifact && releaseSigningConfigurationError != null) {
        throw org.gradle.api.GradleException(
            "$releaseSigningError Cause: $releaseSigningConfigurationError.",
        )
    }
}

flutter {
    source = "../.."
}

dependencies {
    // 16 KB page-size compliance (Google Play, enforced since Nov 2025).
    // mobile_scanner 5.2.3 pulls ML Kit + CameraX whose prebuilt native libs
    // are only 4 KB-aligned (libbarhopper_v3.so, libimage_processing_util_jni.so),
    // which Play now rejects. Force the newer, 16 KB-aligned releases — Gradle
    // version-conflict resolution picks these over mobile_scanner's transitive
    // 17.2.0 / 1.3.3. No Dart-side scanner API change. CameraX modules are kept
    // on one matching version to avoid cross-module runtime mismatches.
    implementation("com.google.mlkit:barcode-scanning:17.3.0")
    implementation("androidx.camera:camera-core:1.4.2")
    implementation("androidx.camera:camera-camera2:1.4.2")
    implementation("androidx.camera:camera-lifecycle:1.4.2")
}
