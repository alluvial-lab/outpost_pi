pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

// These upstream plugins already skip KGP when built-in Kotlin is enabled, but
// Flutter 3.44's lexical warning scan mistakes their AGP-8 fallback branches
// for incompatible unconditional KGP use. Point Gradle at version-pinned build
// overlays until the app's next-story AGP-9 flip removes legacy mode entirely.
for (pluginName in listOf("app_settings", "flutter_image_compress_common", "mobile_scanner")) {
    findProject(":$pluginName")?.let { plugin ->
        val overlay = file("plugin-builds/$pluginName.gradle")
        plugin.buildFileName =
            plugin.projectDir.toPath().relativize(overlay.toPath()).toString()
    }
}

include(":app")
