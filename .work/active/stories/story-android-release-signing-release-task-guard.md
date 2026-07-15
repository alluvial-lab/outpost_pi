---
id: story-android-release-signing-release-task-guard
kind: story
stage: implementing
tags: [app, bug, security, release]
parent: epic-rebrand-external-surfaces
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-15
updated: 2026-07-14
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
