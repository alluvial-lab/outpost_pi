---
id: feature-outpost-pi-distribution-ownership-ci-signing
kind: story
stage: done
tags: [rebrand, release, security, cockpit, app]
parent: feature-outpost-pi-distribution-ownership
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
---

# Parameterize CI signing and clean up inherited identity metadata

Implements Unit 2 of `feature-outpost-pi-distribution-ownership`.

## Scope

- `.github/workflows/cockpit-release.yml`: remove hard-coded `SIGN_ID: "Developer ID Application: Jacob Moura (U843T2P7A2)"`; read `APPLE_SIGNING_IDENTITY` and `APPLE_TEAM_ID` from secrets/inputs; fail closed (error step) when absent.
- `cockpit/distribute_options.yaml`: `APPLE_SIGNING_IDENTITY` → reference the secret/env var, not the literal Jacob identity.
- `cockpit/packaging/README.md` signing section: document the parameterized identity and the fail-closed posture; remove the literal Jacob Developer ID from the `codesign` examples.
- `app/packages/outpost_pi_identity/ios/outpost_pi_identity.podspec`: homepage `jacob-moura/remote_pi` → `KevounC/outpost_pi`; author → Outpost-Pi / Kevoun.
- Android keystore naming cleanup: `remotepi-release.jks` / alias `remotepi` → `outpostpi-release.jks` / alias `outpostpi` across `.github/workflows/app-release.yml`, `app/store_listing.md`, and `app/android/app/build.gradle.kts` comments. The fail-closed behavior is already done (story `gate-security-release-build-debug-signing-fallback`); this is only the naming.

## Verification

- `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/cockpit-release.yml'))"`
- `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/app-release.yml'))"`
- `rg 'Developer ID Application: Jacob Moura|jacob-moura/remote_pi|remotepi-release' .github/ cockpit/ app/` returns no hits (excluding historical CHANGELOG).

Note: do not run a full `flutter build apk` (memory-expensive on this VM). The keystore rename is a config/comment change; the fail-closed behavior was verified by the prior story.

## Implementation notes

- Parameterized the macOS signer and Apple team through `APPLE_SIGNING_IDENTITY` and `APPLE_TEAM_ID` GitHub secrets. The release job fails before certificate import when either is absent, then verifies the imported keychain contains the requested signing identity before `codesign` uses it.
- Removed the committed Fastforge signing identity and documented the environment/CI-secret signing contract in the packaging runbook.
- Updated the identity podspec homepage and author to `Outpost-Pi` / `contact@kevoun.com`.
- Renamed the Android release keystore path and documented alias to `outpostpi`. `app/android/app/build.gradle.kts` had no inherited keystore name in comments, so its existing fail-closed release-signing behavior was left unchanged.
- Verified both release workflow YAML files parse with PyYAML and the required inherited-identity search returns no matches. No full APK build was run, per the story scope.

## Review (2026-07-15)

**Verdict**: Approve - story verified by implement; fast-lane advance

**Blockers**: none
**Important**: none
**Nits**: none

**Notes**: Fast-lane: green build+test verification recorded by implement. Orchestrator re-verified the combined tree (extension 838 passed/3 skipped; relay all green; app analyze clean + 698 passed; protocol check + generate:rust:check clean; site lint+build clean).
