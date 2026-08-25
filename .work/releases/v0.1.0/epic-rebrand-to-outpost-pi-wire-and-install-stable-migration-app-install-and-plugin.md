---
id: epic-rebrand-to-outpost-pi-wire-and-install-stable-migration-app-install-and-plugin
kind: story
stage: done
tags: [rebrand, app, lifecycle]
parent: epic-rebrand-to-outpost-pi-wire-and-install-stable-migration
depends_on:
  - epic-rebrand-to-outpost-pi-wire-and-install-stable-migration-regen-generated
release_binding: v0.1.0
gate_origin: null
created: 2026-07-11
updated: 2026-07-12
---

# App auth constant + install identifiers + identity plugin rename

## Scope

Unit 6 of the wire-stable migration feature. Rename the app-side auth
constant, the Android `applicationId`/namespace, the iOS bundle id, and
fully rename the `remote_pi_identity` Flutter plugin package to
`outpost_pi_identity` (directory, pubspec, Dart lib, Kotlin class, package
path).

## Units implemented
- Unit 6 (app install + plugin)

## Changes
- `app/lib/data/transport/ws_transport.dart` (line 34):
  `relayAuthDomainPrefix = utf8.encode('remote-pi-relay-auth-v1\n')` →
  `'outpost-pi-relay-auth-v1\n'`
- `app/android/app/build.gradle.kts` (lines 25, 39):
  `namespace`/`applicationId` `work.jacobmoura.remotepi` →
  `dev.kevoun.outpostpi`
- `app/ios/Runner.xcodeproj/project.pbxproj` (6 occurrences):
  `work.jacobmoura.remotepi.app` → `dev.kevoun.outpostpi.app`
- Plugin package rename:
  - `git mv app/packages/remote_pi_identity app/packages/outpost_pi_identity`
  - `pubspec.yaml` `name: remote_pi_identity` → `outpost_pi_identity`
  - `git mv lib/remote_pi_identity.dart lib/outpost_pi_identity.dart` +
    update its `library` declaration
  - `android/build.gradle.kts` namespace `dev.remotepi.identity` →
    `dev.kevoun.outpostpi.identity`
  - `git mv` Kotlin sources
    `android/src/main/kotlin/dev/remotepi/identity/` →
    `android/src/main/kotlin/dev/kevoun/outpostpi/identity/`
  - `RemotePiIdentityPlugin.kt` → `OutpostPiIdentityPlugin.kt` + class
    rename + `package` declaration update
  - `BlockStoreStore.kt` `package` declaration update
  - `app/pubspec.yaml`: update the path dependency `name` to
    `outpost_pi_identity`
- Update `app/packages/outpost_pi_identity/README.md` references

## Acceptance Criteria
- [x] `flutter analyze` (in `app/`) clean
- [x] `flutter test` (in `app/`) green
- [x] Android namespace + applicationId read `dev.kevoun.outpostpi`;
      iOS bundle id reads `dev.kevoun.outpostpi.app` (all 6 pbxproj
      occurrences)
- [x] Kotlin compiles under the new `dev.kevoun.outpostpi.identity` package
      path (no stale `dev.remotepi.identity` references)
- [x] `grep -rn 'work.jacobmoura.remotepi\|dev.remotepi.identity\|remote_pi_identity\|remote-pi-relay-auth' app/` returns nothing (excluding `.dart_tool/`, `build/`)

## Implementation notes
- Delivery mode: direct-read inline implementation; the story named the complete integration surface, so no exploratory agent was needed.
- Files changed: app relay-auth constant; Android/iOS app install identifiers and main Android package path; app/plugin pubspecs and lockfiles; Dart imports/tests; the complete identity plugin package (Dart barrel, native registration, channels, Android package/class, iOS pod/class, README); and example Android/iOS identifiers/package paths.
- Git moves performed: `app/packages/remote_pi_identity` → `app/packages/outpost_pi_identity`; `lib/remote_pi_identity.dart` → `lib/outpost_pi_identity.dart`; Android Kotlin package sources `dev/remotepi/identity` → `dev/kevoun/outpostpi/identity`; `RemotePiIdentityPlugin.kt` → `OutpostPiIdentityPlugin.kt`; example `MainActivity.kt` into `dev/kevoun/outpostpi/outpost_pi_identity_example`; `remote_pi_identity.podspec` → `outpost_pi_identity.podspec`; `RemotePiIdentityPlugin.swift` → `OutpostPiIdentityPlugin.swift`; and the app `MainActivity.kt` into `dev/kevoun/outpostpi`.
- Tests added: none; this is a mechanical identifier/package migration covered by existing app and plugin tests.
- Verification: `flutter analyze --no-pub` passed with no issues; a second full `flutter test` passed (683 tests); plugin-local `flutter test` passed (17 tests); `git diff --check` passed; the requested stale-identifier grep returned no matches; main and example Android/iOS identifier counts were checked (six iOS occurrences each).
- First full app test attempt exposed two unrelated timing flakes (`debug_log_impl_test` and `sync_service_test`); both passed in a focused rerun, and the subsequent full 683-test run passed.
- Discrepancy from design: the Dart barrel keeps the analyzer-preferred anonymous `library;` directive rather than a named library; all package/file references use `outpost_pi_identity`.
- Unit 8 ownership preserved: this implementation did not edit the Android `BLOB_KEY` or iOS Keychain service. Concurrent Unit 8 work changed those values in the shared working tree while this story was running.
- Shared-tree note: another concurrent process committed the shared Unit 6 + Unit 8 working tree as `88f2807` while this implementation was in progress. This agent did not run `git commit`, per operator instruction; the only remaining uncommitted Unit 6 change is this updated story record.
- Adjacent issues parked: none.
