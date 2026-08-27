---
id: story-migrate-app-agp9-built-in-kotlin
kind: story
stage: done
tags: [app, deps]
parent: feature-stack-currency-review
depends_on: [story-refresh-app-compatible-dependencies, story-migrate-outpost-pi-identity-built-in-kotlin, story-upgrade-app-settings-built-in-kotlin, story-upgrade-plus-plugins-built-in-kotlin, story-resolve-speech-to-text-built-in-kotlin]
release_binding: null
gate_origin: null
created: 2026-08-27
updated: 2026-08-28
---

# App: AGP 9 + flip built-in Kotlin on (all plugins migrated)

App-side KGP/new-DSL migration; enable built-in Kotlin; APK build + smoke. Gated on all five KGP blockers.

Findings, versions, and citations: feature-stack-currency-review.md (the
research item is the single source of truth for this migration program).
Note: story-unify-flutter-3-44-4-pins was completed at dormancy-setup time
(commit 80d9d8903: all four pins → 3.44.4) and is not spawned separately.

## Implementation notes

- Execution capability: `openai-codex/gpt-5.6-sol`; high-risk Android build-chain
  migration carried inline through debug, signed release, and APK inspection.
- Review weight: standard default; this child-story checkpoint closes directly
  after green verification without an independent story review.
- Files changed: app Android settings/module/properties/wrapper and warning
  overlays; app Flutter pin surfaces and 3.47 lock/analyzer migrations; two Dart
  sites surfaced by the 3.47 analyzer; current app/toolchain guidance.
- Tests added/removed: none. Existing 987-test suite and 33 targeted speech tests
  cover the unchanged behavior; the two lint repairs make returned futures await
  inside their owning `try`/`finally` boundaries.
- Simplification: removed app-side `kotlin-android` application and old
  `android.kotlinOptions`; AGP's built-in compiler now owns Kotlin and the app
  uses top-level `kotlin.compilerOptions` at JVM 17.
- Discrepancies from design: built-in Kotlin is unsupported by Flutter 3.44, and
  a 3.44 build confirmed failure, so the required app-facing Flutter 3.47.1 pins
  and lock migration landed with this capstone. The separate
  `android.newDsl=false` opt-out remains because Flutter 3.47.1 fails while
  applying its Gradle plugin when AGP's new DSL implementation is enabled; this
  is not the built-in-Kotlin/KGP opt-out.
- Adjacent issues parked: none. The downstream Flutter story retains the physical
  Pixel Fold stale-IME/UAT evidence gate; no speech beta/AGP-9 friction appeared.

## Overlay disposition

All three version-pinned overlays remain. An unmodified AGP-9/built-in-Kotlin
build proved that `app_settings` 9.0.0, `flutter_image_compress_common` 1.1.1,
and `mobile_scanner` 7.4.0 skip KGP successfully but Flutter 3.47's lexical
scanner still reports their inactive `apply plugin: 'kotlin-android'` branches.
Restoring the scanner-safe `pluginManager.apply` overlays removed all three
false warnings without changing the fallback conditions. Their README now makes
warning-free unmodified hosted builds the removal condition.

## Closure evidence

- Toolchain: Flutter 3.47.1 / Dart 3.13.1; AGP 9.1.0; Gradle 9.3.1; declared
  Kotlin 2.4.0 consumed by AGP built-in Kotlin without applying legacy KGP.
- `flutter analyze`: no issues. Flutter 3.47 introduced four
  `unawaited_return_in_try_block` findings; all were repaired at their actual
  `try`/`finally` ownership boundaries.
- Targeted `speech_to_text` service/ViewModel/widget suite: 33 passed; no beta
  friction after the flip.
- Full `flutter test --exclude-tags e2e --concurrency=2`: 987 passed.
- `flutter build apk --debug`: passed with zero legacy-KGP warnings (app and
  plugins) and zero other build warnings.
- `flutter build apk --release`: passed and produced the signed 83.5 MB fat APK.
  The first attempt exposed the AGP-9 release graph's 512 MiB metaspace ceiling;
  raising the existing capped Gradle metaspace to 768 MiB made the clean retry
  pass without restoring the old 3 GiB heap.
- Slim-equivalent `--target-platform android-arm64` release: passed, signed, and
  produced a 32.4 MB APK. `aapt2 dump badging` reported package
  `dev.kevoun.outpostpi`, version `0.9.0`/code `22`, compile SDK 36, and only
  `arm64-v8a`; `apksigner verify` passed using APK Signature Scheme v2.
- Local `android/key.properties` and signer env remained mode 0600 and untracked;
  no generated APK, heap dump, or signing material is committed.
