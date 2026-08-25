# Flutter's generated registrant references plugins directly, while plugin AARs
# provide their own consumer rules. Keep the embedding entry points reached from
# native code so R8 cannot remove them when optimizing the release-only build.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }

# The embedding contains optional Play deferred-component adapters even when
# this sideload APK does not enable deferred components or depend on Play Core.
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**
