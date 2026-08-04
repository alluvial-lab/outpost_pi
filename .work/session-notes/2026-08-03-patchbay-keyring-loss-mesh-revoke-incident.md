# Incident — patchbay keyring loss → silent re-identity → owner-mesh eviction

**Date:** 2026-08-03
**PC:** `patchbay` (workstation, a sibling Pi in the operator's mesh)
**Trigger observed:** operator ran `/new` in patchbay's Pi terminal.

## What the operator saw

- `✓ New session started`
- `[outpost-pi] Joined local mesh as "patchbay" (follower)`
- `[outpost-pi] keyring unavailable; using file-backed identity at /home/agent/.pi/remote/identity.json. Error: Couldn't access platform storage: KeyRevoked`
- `🟢 Local mesh: connected as "patchbay" (12 peers)` / `🟢 Relay: on, waiting for an app to connect (http://100.106.7.70:3300)`
- `[outpost-pi:mesh-revoked]` — "🔒 Revoked by Owner … The mobile app for this Owner removed this PC from the mesh. Re-pair via /outpost-pi pair if this was unexpected."

## Root cause (one causal chain)

1. **`KeyRevoked`** — patchbay's platform keyring became inaccessible (entry gone /
   locked / unfindable — possibly the 0.1.0 rebrand cutover: the keyring service was
   renamed to `dev.outpostpi.pi`, so a key stored under the old name is unfindable).
2. **File-backed identity fallback** (`pi-extension/src/pairing/storage.ts`) —
   `~/.pi/remote/identity.json` was used. The storage design INTENT is that this is
   transparent: keyring primary, file mirrors the SAME keypair ("use if present,
   never regenerate" — there's a test for "persistent keyring failure but file
   exists → returns the FILE key, never regen").
3. **BUT the file keypair had diverged from the key the owner app originally paired
   with** → the fallback was NOT transparent → patchbay silently re-identified.
4. New pubkey → owner's peer list no longer contains patchbay → the **selfRevoke
   poller** (`pi-extension/src/mesh/self_revoke.ts`, started by
   `pairing_coordinator.ts:390`) reconciled owner-membership on its periodic tick,
   found patchbay missing, and fired `onRevoke` →
   `pairing_coordinator.ts:376-383` emitted `[outpost-pi:mesh-revoked]` and
   detached the owner (`session_replaced`).

## Was `/new` the cause? — No, fully incidental

`/new` is a **session-lifecycle** event; the incident is on the **relay/pairing +
identity** surface. They don't touch:

- **Identity/keyring is loaded at relay/pairing startup** (`ensureSelfRevoke(relayUrl, keypair)`,
  `pairing_coordinator.ts:190/390`), not on session commands. The `KeyRevoked` +
  file-fallback happened at startup.
- **The selfRevoke poller is explicitly relay-lifecycle-owned** (`index.ts:945`:
   "The poller is relay-lifecycle-owned") — started/stopped with the relay, not with
   session lifecycle. `/new` neither starts nor stops it.
- **`/new`** (`composition_root.ts:170`, reason `"new"`) only classifies the session
   reason for logging/projection and mints a new session id.

So `/new` caused neither the keyring failure nor the re-identity nor the eviction.
The operator happened to be interacting with patchbay (ran `/new`) when the
already-true revocation was detected by the poller's periodic tick. The `✓ New session
started` line confirms `/new` itself succeeded.

## Two different "mesh" concepts (don't conflate)

- **Local agent-network mesh** — "Joined local mesh as patchbay (follower), 12 peers"
  = the LAN/tailnet Pi↔Pi mesh. **Healthy**; patchbay is connected locally.
- **Owner-app pairing mesh** — the relay-based owner channel. **This** is what got
  revoked (pubkey mismatch). Only the owner pairing broke.

## Resilience gap (the real bug to track)

The storage design intends keyring loss to be **transparent** (file mirrors the
keypair). On patchbay it was **silently destructive**: the file keypair had diverged,
so the fallback re-identified the PC and got it evicted from the owner mesh — with no
indication until the revocation notice. The gap is in the identity-fallback path:
either the file didn't mirror the keyring key (write-through missing), or the
fallback minted/used a different key rather than failing fast.

**Fix direction (for a backlog item):**
- Ensure the file identity is **write-through** from the keyring at mint time so loss
  is transparent (the design intent), AND/OR
- When the keyring is unreadable AND the file key doesn't match a known-paired owner
  key, **fail fast / warn loudly** rather than silently re-identifying and getting
  evicted. Silent re-identity on fallback is the bug.

## Recovery

`/outpost-pi pair` on patchbay re-pairs it with the owner app.

## Open diagnostic (to confirm on patchbay)

1. Compare the pubkey in `~/.pi/remote/identity.json` against the pubkey the owner
   app has stored for patchbay. Divergence confirms the silent re-identity.
2. Check patchbay's keyring state — is the `dev.outpostpi.pi` entry present? Locked?
   Gone (rebrand cutover under the old `remote-pi` name)? The `KeyRevoked` trigger
   determines whether this is a one-off keyring corruption or the rebrand cutover
   hitting a not-yet-re-paired PC.
