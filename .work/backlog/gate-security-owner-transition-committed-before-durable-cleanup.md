---
id: gate-security-owner-transition-committed-before-durable-cleanup
created: 2026-07-24
updated: 2026-07-24
tags: [security]
---

# Owner transition is committed before cleanup becomes durable

## Source
gate-security scan for v0.3.0 (2026-07-24). Severity: Medium → parked per gate_finding_routing.

## Domain
Data Protection

## Location
`app/lib/pairing/owner_identity_bridge.dart:148`

## Evidence
The watch handler assigns _current = incoming before PairingStorage.wipeAll(). That wipe performs sequential secure-storage deletions without a durable transition marker. If it fails, onReset() never runs (disconnect + transcript wipe skipped); later events with the same incoming key are ignored; a restart loads that key normally and does not retry cleanup. A partial storage failure can leave the replacement Owner active with residual prior-Owner pairings, channel keys, rooms, and transcripts — defeating the v0.3 owner-transition isolation boundary.

## Remediation direction
Persist a pending Owner-transition record before changing the active identity. Gate access while cleanup is pending, make pairing and transcript cleanup boot-convergent, and commit _current only after the complete transition succeeds. NOTE: operator may want to promote this to release-blocking — same boundary as the owner-identity-transition feature.
