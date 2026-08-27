# Built-in-Kotlin warning overlays

The app runs AGP 9 with built-in Kotlin enabled. These three hosted plugins are
compatible with that mode and skip their legacy KGP fallback, but Flutter 3.47
still scans build files lexically and mistakes the inactive
`apply plugin: 'kotlin-android'` lines for actual KGP application.

`android/settings.gradle.kts` selects the checked-in build overlay for each
plugin. Each overlay is the hosted release's Android build file with one
behavior-preserving change: the conditional fallback uses
`pluginManager.apply('kotlin-android')`. Under the app's built-in-Kotlin mode the
condition remains false, so none of these plugins applies KGP.

| Overlay | Hosted source version |
|---|---:|
| `app_settings.gradle` | 9.0.0 |
| `flutter_image_compress_common.gradle` | 1.1.1 |
| `mobile_scanner.gradle` | 7.4.0 |

When one of these packages changes, copy its new Android build file into the
matching overlay, reapply only the `pluginManager.apply` spelling, update this
version table, and run `flutter build apk --debug`. The build must report zero
legacy-KGP warnings. Remove an overlay only after the Flutter warning scanner or
the hosted plugin's fallback spelling changes so an unmodified build remains
warning-free.
