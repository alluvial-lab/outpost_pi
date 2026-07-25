---
id: gate-security-owner-transition-committed-before-durable-cleanup
kind: story
stage: done
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

## Implementation discovery
The transition coordinator is split across `app/lib/pairing/owner_identity_bridge.dart` and the out-of-scope `app/lib/routing/app_router.dart`. The router currently performs disconnect, transcript cleanup, and boot reload through the `onReset` callback only after the bridge assigns `_current`; moving that commit behind the complete cleanup requires changing the callback/boot coordination in `app/lib/routing/` as well as bridge tests. A bridge-only change would either retain the existing early commit or make the router reload against an uncommitted identity, so it cannot meet the atomicity and boot-convergence acceptance criteria within this worker's write scope.

## Implementation notes

- Added a durable `PairingStorage` pending-transition marker. The bridge writes
  it before exposing a replacement key, hides identity/keypair access while it
  exists, and returns `OwnerTransitionPending` at boot rather than loading the
  incoming identity normally.
- Router ownership now performs the shared cleanup sequence (pairing wipe,
  disconnect, transcript wipe, mesh watermark reset). Only after that sequence
  succeeds does the bridge clear the marker and commit `_current`; any failure
  leaves the gate durable for the next boot retry.
- Added bridge coverage for partial secure-storage deletion failure and boot
  recovery, plus router coverage that verifies boot cleanup precedes identity
  commit. Updated the mesh watch test for the explicit transition callback.
- `SyncRequiredPage._recheck` now catches fatal identity-store reads and renders
  an actionable retry error after its async mounted guard.
- Verification: `flutter analyze` passed; focused pairing/router/mesh tests
  passed. The broad non-e2e command was attempted but timed out after existing
  `sync_service_test.dart` degradation/index failures and unrelated
  secure-storage plugin failures in `pairing_viewmodel_test.dart`.

## Review

Bounded inline review (orchestrator, 2026-07-24): the bridge+router redesign
meets all four acceptance points — durable marker written FIRST (outside
wipeAll prefixes), identity committed only after pairing wipe + disconnect +
transcript wipe + watermark reset, boot-convergent resume via
OwnerTransitionPending, and access gated while pending (currentIdentity/
currentOwnerPk null, requireKeyPair throws). Watch events serialized and
dropped while pending; failure paths fail-closed (marker persists, next boot
resumes). Sync-required _recheck now surfaces fatal reads. Orchestrator-
verified on the integrated tree: flutter analyze clean, 117 focused tests
green. Approved -> done.
