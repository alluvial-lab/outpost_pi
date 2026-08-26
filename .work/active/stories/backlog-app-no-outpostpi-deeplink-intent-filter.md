---
id: backlog-app-no-outpostpi-deeplink-intent-filter
kind: story
stage: drafting
tags: [app, bug]
parent: null
depends_on: []
release_binding: null
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
