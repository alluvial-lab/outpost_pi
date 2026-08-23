---
id: idea-app-built-in-kotlin-migration
created: 2026-08-23
updated: 2026-08-23
tags: [app]
---

The Flutter 3.44.4 debug APK build warns that `app/android/app/build.gradle.kts` and several Android plugins still apply the Kotlin Gradle Plugin. A future Flutter version will reject this setup; revisit Flutter's Built-in Kotlin migration before upgrading the app toolchain.
