---
id: story-mesh-reconciliation-deletes-pairing-channel
kind: story
stage: drafting
tags: [bug, app, security]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-27
updated: 2026-07-27
---

# Mesh reconciliation deletes the local pairing's channel keys (pairing oscillation)

## Impact
Twice in 24h the phone's pairing for codebox lost its channel keys,
brick-ing the app ("Relay Offline" forever, factory throws
`PeerChannelError: paired peer predates owner-channel protection; re-pair
required` — verified via instrumented `lifecycleFailure/retryConnect`
capture, debug/965 series). Both times a re-pair worked until the next
cold-start pull. Pre-v0.3.0 this class did not occur.

## Evidence
- Instrumented capture: every cold-start dial fails with `PeerChannelError`
  pre-network (relay sees zero attempts).
- `_writePeer` never strips an existing channel (code-verified): deletion
  must come from the reconciliation loops in `mesh_sync_service.dart`
  (`_replaceLocalCacheWith` keep-set delete, or
  `_restoreProtectedLocalSnapshot` protected-set delete), which
  `deletePeerSilent` any local record whose epk is absent from the pulled
  owner-signed blob.
- Oscillation signature: extension publishes membership {phone epks};
  phone publishes {pi epks}. 2026-07-27 00:47 sequence: "Paired with
  Android device" then "Revoked by Owner o4bghjDo…" — the phone's blob
  lacked the pi because the phone's pull had just deleted its own pi
  record per the extension's blob, and vice versa.
- First incident (04:59→15:37 2026-07-26) was mis-attributed to an owner
  transition; the fingerprint key exists merely because the code
  initializes it on first boot. No transition likely ever fired.

## Suspected root
The pulled blob is treated as authoritative for FULL mesh membership while
each publisher only publishes its own pairings; LWW versions oscillate and
each side's reconciliation deletes the other's latest member (with its
channel keys). Alternatively a narrower epk-keying mismatch (blob member
key vs local record key) makes a correct blob fail to "keep" the local
record.

## Direction
- Reproduce in a test: extension-authored blob missing the local pi epk →
  pull → assert the local channel-keyed record is preserved (it is not
  today).
- Decide the membership model: blob must either be the union of all
  members (publish merges, never replaces what it doesn't know), or
  reconciliation must never delete channel-bearing records on blob
  authority alone (channel keys are device-local; deleting them is
  unrecoverable without re-pair).
- Until fixed, every cold start risks bricking the phone pairing.
