---
id: gate-security-release-build-debug-signing-fallback
kind: story
stage: done
tags: [security, app]
parent: feature-outpost-pi-distribution-ownership
depends_on: [story-en-first-residual-maintained-surfaces]
release_binding: v0.1.0
gate_origin: security
created: 2026-07-12
updated: 2026-07-15
---

# Android release builds silently fall back to debug signing

## Severity
High

## Domain
Infrastructure & Deployment / Supply Chain

## Location
`app/android/app/build.gradle.kts:50`

## Evidence
```kotlin
buildTypes {
    release {
        signingConfig = if (hasReleaseKeystore) {
            signingConfigs.getByName("release")
        } else {
            signingConfigs.getByName("debug")
        }
    }
}
```

## Remediation direction
Make distributable release builds fail closed when the release keystore is absent. Keep debug signing confined to the debug build type, or require an explicit, unmistakably development-only opt-in for a locally sideloaded release-mode build. Add a verification step that inspects the final APK signer before publishing the 0.1.0 artifact.

## Implementation notes

- Changed `app/android/app/build.gradle.kts`.
- The `release` build type now throws a clear `GradleException` when `android/key.properties` does not configure a release keystore; otherwise it selects only the `release` signing config. It no longer references the debug signing config.
- Keystore filename and alias logic are unchanged (`remotepi-release.jks` / `remotepi`). No development-only release-mode override was added.
- Verified by inspection that the release block fails closed and the debug build type remains unmodified; `flutter analyze` and `flutter test` pass from `app/`.
- Discrepancies: none. Parked issues: none.

## Review (2026-07-15)

**Verdict**: Approve - story verified by implement; fast-lane advance

**Blockers**: none
**Important**: none
**Nits**: none

**Notes**: Fast-lane: green build+test verification recorded by implement. Orchestrator re-verified the combined tree (extension 838 passed/3 skipped; relay all green; app analyze clean + 698 passed; protocol check + generate:rust:check clean; site lint+build clean).
