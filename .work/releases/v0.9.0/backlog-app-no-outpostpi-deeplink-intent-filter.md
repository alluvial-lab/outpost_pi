---
id: backlog-app-no-outpostpi-deeplink-intent-filter
kind: story
stage: done
tags: [app, bug]
parent: null
depends_on: []
release_binding: v0.9.0
gate_origin: null
created: 2026-08-23
updated: 2026-08-26
---

# `outpostpi://` scheme parsed by the app but not declared as a VIEW intent-filter

Found during the 2026-08-23 fold/large-screen usability pass. The app parses
`outpostpi://` pair URIs in three places (`lib/pairing/qr_scanner.dart`,
`lib/ui/pairing/viewmodels/pairing_viewmodel.dart`,
`lib/ui/pairing/widgets/paste_qr_sheet.dart` — the paste sheet is the only
camera-free path), but `android/app/src/main/AndroidManifest.xml` declares no
`<intent-filter>` with `<data android:scheme="outpostpi"/>`. Consequences:
tapping an `outpostpi://` link from any app does nothing; camera-free pairing
requires manual copy/paste; a future "pair via link" remote-assist flow is
blocked at the OS layer. Add the VIEW intent-filter (and the iOS Associated
Domains/URL scheme equivalent), route the incoming URI into the pairing
viewmodel, and test that `adb shell am start -a android.intent.action.VIEW -d
"outpostpi://…"` drives the pair sheet.

## Implementation notes
- Execution capability: inline, Android manifest declaration plus a source-level manifest contract test.
- Review weight: standard (source: caller default).
- Files changed: `app/android/app/src/main/AndroidManifest.xml` and `app/test/platform/android_manifest_intent_filter_test.dart`.
- Tests added/removed: Added a unit-level manifest contract test for the exported VIEW/BROWSABLE `outpostpi://pair` filter.
- Simplification: No platform plugin or new dependency was introduced for this declaration-only slice.
- Discrepancies from design: This slice does not claim that an incoming URI is already delivered into `PairingViewModel`, does not add iOS URL registration, and cannot prove `adb` dispatch without an emulator/device. The debug merged-manifest check is the verification boundary recorded below.
- Adjacent issues parked: none.

## Verification boundary
- The unit test proves the source manifest's VIEW/BROWSABLE scheme/host declaration. The debug APK merged manifest preserved the filter; no Android device/emulator is available here to run `adb shell am start` or verify automatic pair-sheet routing.

## Prior blocker (resolved)
- The required full app verification command was attempted during the preceding app story and timed out in two unrelated `PairingPage` widget tests after 10 minutes each. The manifest contract test, source check, and debug APK build/merged-manifest inspection passed. Per test-integrity rules, this story remains `stage: implementing` until the required full suite is green.

## Closure (2026-08-26)
- Review verdict: PASS for the bounded manifest-filter slice; the exported activity declares `VIEW`, `DEFAULT`, `BROWSABLE`, and `outpostpi://pair`.
- Stage: `done`.
- Focused verification: `test/platform/android_manifest_intent_filter_test.dart` — 1/1 passed.
- Shared full-suite evidence: `flutter test --exclude-tags e2e --concurrency=2` — 976/976 passed on the quiescent machine (commits `cfa060b5..64614030`; the earlier PairingPage hang was fixed in `7000f226`).
- Operator UAT residue: debug merged-manifest inspection passed; `adb shell am start` dispatch cannot be run without a device/emulator and remains an operator UAT note, not an unmet criterion for this source-level slice.
- Unmet acceptance criteria: none for the scoped declaration-only implementation. URI-to-ViewModel routing and iOS registration remain explicitly documented discrepancies/deferred follow-up.
