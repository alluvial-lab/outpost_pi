---
id: gate-security-identity-store-fatal-read-rotates-owner-key
kind: story
stage: implementing
tags: [security]
parent: null
depends_on: []
release_binding: v0.3.0
gate_origin: security
created: 2026-07-24
updated: 2026-07-24
---

# Fatal identity-store reads can silently rotate the Owner key

## Source
gate-security scan for v0.3.0 (2026-07-24). Severity: Medium → **promoted to
release-blocking by operator decision 2026-07-24** (defeats the v0.3
owner-transition boundary on a partial-failure path).

## Domain
Data Protection / Error Handling

## Location
`app/lib/pairing/owner_identity_bridge.dart:75`

## Evidence
boot() catches every IdentityStoreError and treats it like an absent first-run identity — including PlatformFailure, whose store contract classifies corruption/entitlement failures as fatal. The bridge then generates and saves a replacement key. A transient read failure followed by a successful write can overwrite the durable Owner identity, strand existing pairings, and let the new principal inherit old local peer/transcript state without running the confirmed-transition cleanup.

## Remediation direction
Generate only when load() returns null. Return the sync-required result for SyncUnavailable and propagate or explicitly surface PlatformFailure. Recheck or create conditionally before saving, with tests for read failures and concurrent restoration.

## Acceptance
- A replacement Owner key is generated only when `load()` returns null (genuine first run) — never on an error path.
- `SyncUnavailable` returns the sync-required result; `PlatformFailure` propagates or is explicitly surfaced (no silent rotation).
- Save is conditional/rechecked so concurrent restoration cannot overwrite a durable identity.
- Tests cover fatal read failures and concurrent restoration.
