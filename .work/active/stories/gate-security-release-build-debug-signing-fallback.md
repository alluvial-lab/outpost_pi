---
id: gate-security-release-build-debug-signing-fallback
kind: story
stage: implementing
tags: [security, app]
parent: feature-outpost-pi-distribution-ownership
depends_on: [story-en-first-residual-maintained-surfaces]
release_binding: null
gate_origin: security
created: 2026-07-12
updated: 2026-07-14
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
