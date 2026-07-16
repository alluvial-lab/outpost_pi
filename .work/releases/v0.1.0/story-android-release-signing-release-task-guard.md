---
id: story-android-release-signing-release-task-guard
kind: story
stage: done
tags: [app, bug, security, release]
parent: epic-rebrand-external-surfaces
depends_on: []
release_binding: v0.1.0
gate_origin: null
created: 2026-07-15
updated: 2026-07-15
---

# Fail closed only when an Android release task is requested

## Review finding

**Severity:** Blocker

`app/android/app/build.gradle.kts:60-67` throws while Gradle evaluates the
`release` build-type configuration. That closure runs during configuration for
every Gradle invocation, so a clone without `android/key.properties` cannot run
debug tasks either. The review reproduced this with `./gradlew help --offline`:
with `key.properties` absent, configuration failed at line 62 with the release
keystore error before the requested `help` task could run.

This breaks the documented contributor path in `app/CLAUDE.md:37` and does more
than the intended fail-closed release behavior. Related reference text also
still describes the removed fallback in
`.agents/skills/flutter-mobile/SKILL.md:96` and
`.github/workflows/app-release.yml:7,87,102`.

## Required outcome

- Debug and non-release Gradle tasks configure and run without release signing
  material.
- Any task that produces a release APK/AAB fails before artifact production when
  the release keystore configuration is missing or incomplete.
- The CI signer-fingerprint check remains as defense in depth.
- Roll the mobile reference and app-release workflow comments forward to the
  actual fail-closed contract.
- Add a regression check that exercises one no-key debug/non-release task and
  one no-key release task; the former must pass configuration and the latter
  must fail with the explicit signing error.

## Implementation notes

- Files changed: `app/android/app/build.gradle.kts`,
  `app/android/check_release_signing_guard.sh`,
  `.github/workflows/app-release.yml`, and
  `.agents/skills/flutter-mobile/SKILL.md`.
- Guard: validates all four signing properties plus the keystore file, then
  rejects release APK/AAB task graphs in `gradle.taskGraph.whenReady` before
  any task executes; non-release configuration never throws for absent signing
  material.
- Regression check: `android/check_release_signing_guard.sh` runs no-key
  `gradlew help`, then requires no-key `:app:assembleRelease --dry-run` to fail
  with the explicit signing error. The app-release workflow runs this check
  before restoring CI signing secrets.
- Verification: app `flutter analyze` and all 698 Flutter tests passed; no-key
  `help` passed; no-key `assembleRelease --dry-run` and `bundleRelease
  --dry-run` failed with the explicit guard error. A complete properties file
  pointing at a missing keystore also allowed `help` and rejected release.
- Discrepancies from design: none.
- Adjacent issues parked: none.

## Review (2026-07-15, second pass)

**Verdict**: Approve

**Blockers**: none
**Important**: none
**Nits**: none

**Notes**: Deep-feature second-pass verification confirmed the guard runs from `gradle.taskGraph.whenReady`, no-key `help` succeeds, and no-key `assembleRelease` plus `bundleRelease` task graphs fail with the explicit signing error before execution. The regression script exercises the required non-release and release paths. Story advanced `review -> done`.
