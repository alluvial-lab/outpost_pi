# Built-in-Kotlin compatibility overlays

Flutter 3.44 keeps this app on `android.builtInKotlin=false` until the separate
AGP 9 app migration. Three hosted plugins are already compatible with both
modes, but their Groovy build scripts spell the legacy-only fallback as
`apply plugin: 'kotlin-android'`. Flutter 3.44 scans build files lexically and
reports that conditional line as unconditional legacy KGP use.

`android/settings.gradle.kts` selects the checked-in build overlay for each
plugin. Each overlay is the hosted release's Android build file with one
behavior-preserving change: the conditional AGP-8 fallback uses
`pluginManager.apply('kotlin-android')`. The condition remains unchanged, so KGP
is applied while built-in Kotlin is false and skipped when it is true.

| Overlay | Hosted source version |
|---|---:|
| `app_settings.gradle` | 9.0.0 |
| `flutter_image_compress_common.gradle` | 1.1.1 |
| `mobile_scanner.gradle` | 7.4.0 |

When one of these packages changes, copy its new Android build file into the
matching overlay, reapply only the `pluginManager.apply` spelling, update this
version table, and run `flutter build apk --debug`. The build must report no
plugin KGP warning. Remove the overlays and settings indirection when the app's
AGP-9/built-in-Kotlin migration lands; that mode makes the fallback inactive
and removes the Flutter 3.44 lexical gate.
