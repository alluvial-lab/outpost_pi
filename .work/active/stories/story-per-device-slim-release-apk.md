---
id: story-per-device-slim-release-apk
kind: story
stage: done
tags: [app, workflow, distribution]
parent: null
depends_on: []
release_binding: v0.9.0
gate_origin: null
created: 2026-08-25
updated: 2026-08-25
---

# Per-device slim release APK

After the full-ABI debug candidate passes operator UAT, produce a release-signed,
arm64-only APK for the operator's Pixel Fold. Keep the existing debug artifact as
the UAT fallback while reducing the normal sideload payload from roughly 190 MB
to the 25–35 MB range.

## Required outcome

- Generate a VM-local self-signed upload keystore once at
  `~/.config/outpost-pi/release-upload.keystore.jks`, with a strong password in
  mode-0600 `~/.config/outpost-pi/keystore.env`; no key material enters git.
- Restore Android release signing without weakening the task-graph guard:
  absent/incomplete signing material fails release artifact tasks clearly, while
  debug and configuration tasks remain usable.
- Enable R8 minification and resource shrinking for release builds.
- Add `scripts/release-apk.sh --slim`: build the existing full-ABI debug APK,
  then a release `android-arm64` APK; verify badging, version identity, and
  `lib/arm64-v8a/libflutter.so`; name the artifacts
  `outpost-<version>-<code>.apk` and
  `outpost-<version>-<code>-arm64.apk`; print both sizes.
- Draft-release upload with `--slim` attaches both artifacts so publishing the
  candidate promotes the debug-fat and slim-arm64 APKs together.
- Update the local release/UAT runbook with the two-artifact flow, debug-grade
  trust posture, key location, and key-loss uninstall/reinstall recovery.

## Acceptance

- [x] `flutter analyze` is clean under the repo's documented baseline.
- [x] `flutter test --exclude-tags e2e --concurrency=2` passes.
- [x] The debug-fat and signed slim-arm64 APKs both build through the release
      script and report their sizes.
- [x] `aapt2 dump badging` reports package `dev.kevoun.outpostpi`, versionName
      and versionCode matching between artifacts, and only `arm64-v8a` for the
      slim artifact.
- [x] The slim archive contains `lib/arm64-v8a/libflutter.so` and no
      `libflutter.so` for another ABI.
- [x] The no-key release signing regression guard still proves release tasks
      fail closed without affecting non-release configuration.
- [x] No APK, keystore, password, or local key properties are committed.

## Implementation notes

- Execution capability: `openai-codex/gpt-5.6-sol` at high reasoning; selected
  by the caller for signing, Gradle/R8, artifact verification, and runbook work.
- Review weight: standard (project default); standalone-story bounded inline
  review completed without an independent reviewer.
- Files changed: `.gitignore`, `app/android/app/build.gradle.kts`,
  `app/android/app/proguard-rules.pro`,
  `app/android/check_release_signing_guard.sh`, `scripts/release-apk.sh`,
  `.agents/skills/flutter-mobile/SKILL.md`, `app/CLAUDE.md`,
  `app/store_listing.md`, and local-only `AGENTS.local.md`.
- Local signing state created once: mode-0600
  `~/.config/outpost-pi/release-upload.keystore.jks` (RSA-4096, self-signed,
  10,000-day validity), mode-0600 `~/.config/outpost-pi/keystore.env`, and
  ignored mode-0600 `app/android/key.properties` containing only environment
  references.
- Release behavior: `key.properties` resolves `${env.NAME}` values; missing,
  blank, unresolved, or absent-file signing state fails the existing release
  task graph with the explicit no-debug-fallback error. Debug/configuration
  tasks remain keyless. R8 minification, resource shrinking, Flutter keep
  rules, and generated missing-class suppressions for unused Play deferred
  components are enabled for release.
- Artifact behavior: `scripts/release-apk.sh --slim` builds debug first, builds
  release with `--target-platform android-arm64`, filters plugin AAR native
  padding to arm64, verifies package/version/ABI/archive sentinels/upload-key
  signer, and names both artifacts. Updating an existing candidate draft keeps
  the exact debug APK already UATed and adds/clobbers only the slim artifact.
- Sizes: debug-fat `238,606,377` bytes (`228 MiB`); slim-arm64 `32,491,312`
  bytes (`31 MiB`).
- Structural evidence: both APKs reported package `dev.kevoun.outpostpi`,
  versionName `0.8.0`, versionCode `16`; slim badging was exactly
  `native-code: 'arm64-v8a'`; its only `libflutter.so` was
  `lib/arm64-v8a/libflutter.so`; `AndroidManifest.xml`, `classes.dex`, Flutter
  assets, ML Kit `libbarhopper_v3.so`, and image-processing JNI were present;
  apksigner matched the configured upload certificate.
- Tests added/removed: no product tests; strengthened the signing-guard script
  so it temporarily hides and restores operator-local `key.properties`.
- Verification: `flutter analyze` passed with no issues; all 956 non-e2e tests
  passed at concurrency 2; `scripts/release-apk.sh --slim` passed end-to-end;
  the no-key guard passed; unresolved environment references failed with the
  explicit signing error; a fully resolved signed release dry-run passed.
  The x86_64 emulator was intentionally not used for the arm64 APK. Existing
  release mapping retained mobile-scanner, speech, share, and image-picker
  plugin classes; host tests covered their Dart surfaces.
- Simplification: reused the v0.8.0 per-ABI `libflutter.so` incident guard and
  centralized both debug/slim build, naming, size reporting, draft attachment,
  and signer checks in one script.
- Discrepancies from design: Flutter's `--target-platform android-arm64` limits
  `libflutter.so` but leaves transitive plugin libraries in other ABI dirs;
  Gradle target-aware NDK filters plus packaging exclusions were required for
  exact arm64-only badging. Initial R8 execution also surfaced optional Flutter
  Play-deferred-component missing classes; the generated narrow `dontwarn`
  rules were added.
- Adjacent issues parked: `backlog-google-fonts-test-network-noise`; the suite
  passes but prints failed Space Mono network fetches. The pre-existing
  Built-in Kotlin migration warning was already parked as
  `idea-app-built-in-kotlin-migration`.

## Bounded inline review

Approved. The review re-ran the fail-closed guard with local signing present,
proved unresolved env references fail clearly, verified the configured signer
against the APK, checked exact arm64 badging and archive contents, and confirmed
that no key material or APK is staged for commit.
