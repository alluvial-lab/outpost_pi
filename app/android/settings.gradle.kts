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
    id("com.android.application") version "9.1.0" apply false
    // AGP's built-in compiler consumes this version without applying legacy KGP.
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

// These plugins skip KGP under built-in Kotlin, but Flutter 3.47's lexical
// scanner still mistakes their inactive fallback branches for plugin use.
for (pluginName in listOf("app_settings", "flutter_image_compress_common", "mobile_scanner")) {
    findProject(":$pluginName")?.let { plugin ->
        val overlay = file("plugin-builds/$pluginName.gradle")
        plugin.buildFileName =
            plugin.projectDir.toPath().relativize(overlay.toPath()).toString()
    }
}

include(":app")
