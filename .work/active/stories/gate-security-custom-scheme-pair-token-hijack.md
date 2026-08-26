---
id: gate-security-custom-scheme-pair-token-hijack
kind: story
stage: implementing
tags: [app, security]
parent: null
depends_on: []
release_binding: v0.9.0
gate_origin: security
created: 2026-08-26
updated: 2026-08-26
---

# Android custom-scheme pairing links expose the enrollment token to scheme hijacking

## Severity
High

## Domain
Authentication & Authorization

## Location
`app/android/app/src/main/AndroidManifest.xml:44`

## Evidence
```xml
<intent-filter>
    <action android:name="android.intent.action.VIEW"/>
    <category android:name="android.intent.category.BROWSABLE"/>
    <data android:scheme="outpostpi" android:host="pair"/>
</intent-filter>
```

The browsable URI contains the raw, single-use pairing token (`app/lib/pairing/qr_scanner.dart:3-8`). Android custom schemes are not application-exclusive, so another installed app can register the same scheme and receive a link the user opens. Possession of that token lets the intercepting app generate its own Owner key and satisfy the pair proof; the extension then persists that Owner channel (`pi-extension/src/extension/owner_multiplexer.ts:423-455`).

## Remediation direction
Do not carry the enrollment capability through an unverified custom-scheme handoff. Use a verified HTTPS Android App Link bound to an owned domain (with Digital Asset Links) or retain the QR/manual-paste path until an exclusive platform handoff exists. Add an adversarial Android test showing that the selected transport cannot be claimed by a second package before enabling link-driven pairing.
