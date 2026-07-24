---
id: gate-security-owner-transition-committed-before-durable-cleanup
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

# Owner transition is committed before cleanup becomes durable

## Source
gate-security scan for v0.3.0 (2026-07-24). Severity: Medium → **promoted to
release-blocking by operator decision 2026-07-24** (same boundary as the
owner-identity-transition feature).

## Domain
Data Protection

## Location
`app/lib/pairing/owner_identity_bridge.dart:148`

## Evidence
The watch handler assigns _current = incoming before PairingStorage.wipeAll(). That wipe performs sequential secure-storage deletions without a durable transition marker. If it fails, onReset() never runs (disconnect + transcript wipe skipped); later events with the same incoming key are ignored; a restart loads that key normally and does not retry cleanup. A partial storage failure can leave the replacement Owner active with residual prior-Owner pairings, channel keys, rooms, and transcripts — defeating the v0.3 owner-transition isolation boundary.

## Remediation direction
Persist a pending Owner-transition record before changing the active identity. Gate access while cleanup is pending, make pairing and transcript cleanup boot-convergent, and commit _current only after the complete transition succeeds.

## Acceptance
- A durable pending-transition record is written before the active identity changes; `_current` commits only after the full transition (storage wipe + disconnect + transcript wipe) succeeds.
- Cleanup is boot-convergent: a restart with a pending transition retries cleanup instead of loading the incoming key normally.
- Access is gated while a transition is pending.
- Tests cover partial storage failure mid-transition and restart convergence.
