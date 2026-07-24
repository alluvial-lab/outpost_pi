---
id: gate-security-identity-store-fatal-read-rotates-owner-key
created: 2026-07-24
updated: 2026-07-24
tags: [security]
---

# Fatal identity-store reads can silently rotate the Owner key

## Source
gate-security scan for v0.3.0 (2026-07-24). Severity: Medium → parked per gate_finding_routing.

## Domain
Data Protection / Error Handling

## Location
`app/lib/pairing/owner_identity_bridge.dart:75`

## Evidence
boot() catches every IdentityStoreError and treats it like an absent first-run identity — including PlatformFailure, whose store contract classifies corruption/entitlement failures as fatal. The bridge then generates and saves a replacement key. A transient read failure followed by a successful write can overwrite the durable Owner identity, strand existing pairings, and let the new principal inherit old local peer/transcript state without running the confirmed-transition cleanup.

## Remediation direction
Generate only when load() returns null. Return the sync-required result for SyncUnavailable and propagate or explicitly surface PlatformFailure. Recheck or create conditionally before saving, with tests for read failures and concurrent restoration. NOTE: operator may want to promote this to release-blocking — it defeats the v0.3 owner-transition boundary on a partial-failure path.
