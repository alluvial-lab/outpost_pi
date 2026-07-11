---
id: epic-rebrand-to-outpost-pi-wire-and-install-stable-migration-app-install-and-plugin
kind: story
stage: implementing
tags: [rebrand, app, lifecycle]
parent: epic-rebrand-to-outpost-pi-wire-and-install-stable-migration
depends_on:
  - epic-rebrand-to-outpost-pi-wire-and-install-stable-migration-regen-generated
release_binding: null
gate_origin: null
created: 2026-07-11
updated: 2026-07-11
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
- [ ] `flutter analyze` (in `app/`) clean
- [ ] `flutter test` (in `app/`) green
- [ ] Android namespace + applicationId read `dev.kevoun.outpostpi`;
      iOS bundle id reads `dev.kevoun.outpostpi.app` (all 6 pbxproj
      occurrences)
- [ ] Kotlin compiles under the new `dev.kevoun.outpostpi.identity` package
      path (no stale `dev.remotepi.identity` references)
- [ ] `grep -rn 'work.jacobmoura.remotepi\|dev.remotepi.identity\|remote_pi_identity\|remote-pi-relay-auth' app/` returns nothing (excluding `.dart_tool/`, `build/`)
