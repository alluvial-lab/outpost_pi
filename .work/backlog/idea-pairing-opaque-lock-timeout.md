---
id: idea-pairing-opaque-lock-timeout
created: 2026-07-30
updated: 2026-07-30
tags: [pi-extension, security, lifecycle, bug]
---

# Pairing "could not be completed" hides peer-storage lock contention

## Observed (2026-07-30)

Re-pairing the app after a pi restart failed with "Pairing could not be completed"
(`internal_error`). Root cause: multiple pi processes (outpost_pi + 2× patchbay)
shared one owner identity (`~/.pi/remote/`) and contended on the machine-wide
`peers.lock`. The outpost_pi pi's `handlePairRequest` → `addPeer` → `mutatePeers`
could not acquire the lock (held by an orphaned patchbay pi on a detached pts)
within the 2s `PeerStorageLockTimeoutError` window, so the catch block in
`owner_multiplexer.ts:~444` emitted the generic `internal_error` /
"Pairing could not be completed" with no indication of the lock-timeout cause.

## Why it matters

The error message is opaque — it gives the operator no signal that the failure is
lock contention from sibling pi instances sharing the identity, not a pairing
protocol failure. The operator chased several false leads (room mismatch, stale
pairing, copy-paste corruption) before the lock contention was identified.

## Recommended direction

- The `internal_error` catch in `handlePairRequest` should distinguish
  `PeerStorageLockTimeoutError` from a crypto/key-derivation throw and surface a
  specific code/message (e.g. `pair_error code=owner_store_busy` with guidance to
  stop sibling pi processes sharing the identity).
- Consider whether the 2s `DEFAULT_PEER_LOCK_TIMEOUT_MS` is too short when another
  pi is legitimately mutating. (It was sufficient once the contention cleared, so
  this is secondary.)
- Operational doc: note in AGENTS.md that multiple pi processes in different cwds
  but sharing `~/.pi/remote/` contend on the machine-wide `peers.lock` and can
  break pairing opaquely.

## Provenance

Diagnosed during the 2026-07-30 pairing incident chain
(`.work/session-notes/2026-07-30-drain-and-pairing-incident.md`).
