---
id: gate-security-custom-scheme-pair-token-hijack
kind: story
stage: done
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

## Resolution

Chose the verified Android App Link path. This product controls
`outpost-pi.kevoun.com`, and the operator's stable release keystore is already
the single-device sideload trust anchor. The extension now emits the exact link
`https://outpost-pi.kevoun.com/pair#…`; Android accepts only that HTTPS
origin/path with `android:autoVerify="true"`; and the site publishes Digital
Asset Links for package `dev.kevoun.outpostpi` and the configured release
certificate. The custom-scheme filter and parser acceptance were removed.

Enrollment fields are carried in the URI fragment rather than the HTTP query.
Android still delivers the complete verified link to the app, while browser
fallback requests send only `/pair`, keeping the token out of site access logs.
This preserves the camera, paste, headless/Cockpit, and link-opening surfaces
without adding a confirm-code flow or a new app dependency.

## Implementation notes
- Execution capability: `openai-codex/gpt-5.6-sol`, inline direct-read delivery;
  the security-sensitive link contract crossed app, extension, and static site,
  but remained one cohesive pairing boundary.
- Review weight: standard (project default); bounded standalone-story inline
  review completed after integrated verification.
- Files changed: Android manifest and contract test; app pairing parser,
  ViewModel copy, paste UI, and pairing fixtures/tests; extension URI builder
  and pairing tests; site Digital Asset Links and route test; Cockpit's opaque
  pair-code fixture; `.gitignore`; `AGENTS.md`, `PROTOCOL.md`, the Flutter mobile
  reference, and the release UAT runbook.
- Tests added/removed: replaced the custom-scheme manifest assertion with an
  adversarial source contract proving there is no claimable custom-scheme VIEW
  filter and that the only pairing filter is auto-verified HTTPS; added Digital
  Asset Links package/signer assertions; expanded URI parsing tests to reject
  custom schemes, foreign origins/path lookalikes, and enrollment data in HTTP
  queries while accepting the exact fragment form.
- Simplification: removed the spoofable custom-scheme transport in place; no
  confirm-code UI, compatibility filter, platform plugin, or new dependency was
  introduced.
- Discrepancies from design: none. The fragment placement is defense in depth
  beyond the recorded App Links direction and does not change pairing payload
  fields.
- Adjacent issues parked: none.

## Verification
- Configured release-keystore SHA-256 certificate fingerprint matched the sole
  fingerprint in `site/public/.well-known/assetlinks.json`.
- App focused pairing/manifest suite: 29/29 passed.
- `flutter analyze`: no issues.
- `flutter test --exclude-tags e2e --concurrency=2`: 979/979 passed.
- `flutter build apk --debug`: passed; APK manifest inspection confirmed one
  VIEW filter with `autoVerify=true`, HTTPS, `outpost-pi.kevoun.com`, and exact
  `/pair` path.
- Pi extension focused pairing tests: 12/12 passed; `corepack pnpm typecheck`
  and `corepack pnpm build` passed; full `corepack pnpm test`: 1,103 passed,
  3 skipped.
- Site `pnpm lint` and `pnpm build` passed; the production-server Digital Asset
  Links route test passed with HTTP 200 and `application/json`.
- Cockpit pairing-gateway focused test: 4/4 passed.

## Bounded inline review

PASS. The reviewed final surface has no browsable `outpostpi://` filter, the
app rejects custom-scheme and query-carried enrollment payloads, the extension
generates only the exact HTTPS fragment form, and Digital Asset Links binds the
owned host to both the expected package and current release signer. No token or
private key material was committed.

## Closure (2026-08-26)

The source-level release blocker is resolved with verified App Links because an
owned production domain and stable release signing identity make this stronger
and simpler than a confirm-code UX. Operator residue remains deployment/device
verification: deploy the updated site before the extension/app pair, install
the release-signed slim APK, and run the `pm verify-app-links`,
`pm get-app-links`, and dummy-link resolver checks recorded in
`docs/release-uat.md`. No Android device/emulator was available here, so those
package-manager checks were not claimed. If the release key rotates, publish
its new fingerprint before the newly signed APK; never add the debug
certificate to the production association.
