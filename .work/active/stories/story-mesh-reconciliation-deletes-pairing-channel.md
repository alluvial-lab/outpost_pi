---
id: story-mesh-reconciliation-deletes-pairing-channel
kind: story
stage: done
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

## Resolution (2026-07-27, done)

**Confirmed root cause — the narrower epk-keying mismatch, not the
multi-publisher model.** The extension never publishes a mesh blob (its
`MeshClient` is GET-only; `SelfRevoke` only polls), so the app is the sole
publisher. The deterministic brick: `PairingStorage` keys records by the
QR/pair_ok string (base64url) while `_publishOnce` normalizes blob members
to base64 standard. `_replaceLocalCacheWith` matched blob members to local
records by RAW STRING, so for any key whose encodings differ (~3/4 of
random keys) the keep-set check missed → `deletePeerSilent` destroyed the
channel-bearing record and a channel-less duplicate was hydrated under the
standard spelling → next cold start threw `PeerChannelError` pre-network.
Pre-v0.3.0 this was invisible (no channel to lose; the record was
rehydrated). The extension-side "Revoked by Owner" was downstream: once
the phone's record was wiped, the next delete-kind mutation published a
pi-less blob through the `allowEmpty` path and the extension self-revoked.

**Membership-model decision (option 2 + canonical keying).**
- All reconciliation matching is by canonical (standard-b64) epk; a matched
  local record keeps its stored spelling and its channel; new members
  hydrate under the storage-canonical (base64url) spelling so a later
  pairing overwrites instead of duplicating.
- Blob absence is no longer deletion authority for channel-bearing
  records: the LWW blob can lag the local pairing, and channel keys are
  unrecoverable without re-pair. Channel-less (metadata-only) records
  absent from the blob are still deleted, so revocation/roster hygiene
  propagates for records this device never paired. Trade-off: a peer
  genuinely revoked from ANOTHER device leaves a ghost record on this one
  (the Pi self-revoked, so the channel is dead); the user revokes locally.
- Duplicate spellings of one canonical key collapse to the channel-bearing
  (else storage-canonical) record — cleans incident debris on the next
  pull.

**Also fixed (e2e harness, unblocked verification):** the
`pair-code-seam-hardening` refuse-to-overwrite check
(`assertPairCodeTargetAbsent`) broke the e2e suite — the pair-code file
survives host generations inside the container, so only the first `pair`
per container worked (1 pass / 15 fails). The host runtime now wipes the
seam file per generation, and `waitForPairCode` consumes it (DELETE
/pair-code) after observation, mirroring the Cockpit consumer contract.

**Verification:** 3 new failing-then-passing reconciliation tests;
app suite 852/852; `flutter analyze` clean; `e2e/run-pairing.sh` 16/16 +
redaction canaries.
