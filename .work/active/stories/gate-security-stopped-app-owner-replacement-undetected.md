---
id: gate-security-stopped-app-owner-replacement-undetected
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

# Owner identity replaced while the app is stopped boots without cleanup

## Severity
High

## Domain
Data Protection

## Location
`app/lib/pairing/owner_identity_bridge.dart:86-97`; `app/lib/routing/app_router.dart:155-180`

## Evidence
Boot records only a pending-transition bit, not the Owner public key
associated with existing local data. When no marker exists, any loaded or
newly generated identity is immediately assigned to `_current`. The router
then loads existing peers and connects without comparing Owner identities.
Because the watcher is installed after boot, it cannot detect an identity
replacement that occurred while the app was stopped.

## Exploit scenario
Owner A leaves paired devices and encrypted transcripts on a phone. While
the app is stopped, an iCloud/Google account change or sync restore replaces
or removes the Owner identity. Boot activates Owner B — or generates a new
identity — without cleanup, exposing Owner A's local transcripts, peer
metadata, and channel material to the new account.

## Remediation direction
Persist the public-key fingerprint that owns local state. At boot, compare
it with the loaded/generated candidate before assigning `_current`; on
mismatch, write the pending marker and complete the existing cleanup path
first. Update the fingerprint only when transition cleanup commits. Reuses
the drain's begin/complete transition machinery.

## Acceptance
- A durable owner-of-local-state fingerprint exists and is only updated on
  committed transition cleanup.
- Boot with a mismatched loaded/generated identity routes through the
  pending-transition cleanup before activation (no peers/transcripts
  reachable by the new identity pre-cleanup).
- First-run (no fingerprint) behaves as today.
- Tests: stopped-app replacement with existing local state; fingerprint not
  updated on failed cleanup; clean retry commits exactly once.
