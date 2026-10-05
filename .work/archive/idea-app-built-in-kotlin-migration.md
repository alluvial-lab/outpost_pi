---
id: idea-app-built-in-kotlin-migration
created: 2026-08-23
updated: 2026-10-05
tags: [app]
status: superseded
superseded_by: story-migrate-app-agp9-built-in-kotlin
resolved: "2026-10-05 groom: shipped in v0.10.0 — zero legacy-KGP warnings"
---

The Flutter 3.44.4 debug APK build warns that `app/android/app/build.gradle.kts` and several Android plugins still apply the Kotlin Gradle Plugin. A future Flutter version will reject this setup; revisit Flutter's Built-in Kotlin migration before upgrading the app toolchain.
