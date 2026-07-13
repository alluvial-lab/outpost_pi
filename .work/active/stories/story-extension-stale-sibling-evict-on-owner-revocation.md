---
id: story-extension-stale-sibling-evict-on-owner-revocation
kind: story
stage: review
tags: [pi-extension, bug, lifecycle, security]
parent: epic-targeting-and-session-lifecycle-contracts
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-12
updated: 2026-07-13
implemented: 2026-07-13
root_cause_confirmed: 2026-07-13
---

# Extension keeps spamming a revoked sibling Pi epk → `pi_envelope not_authorized` loop

## Observed (2026-07-12, live relay log)

After re-pairing under a new Owner (the 5 prior Owners `DcO7M297`, `hjh7eAvN`,
`my/xN94M`, `WkH5bCEq`, `ifnAttdc` were revoked and a fresh mesh was created
for Owner `SBWY…iwT+dXs=`), the extension's cross-PC agent-mesh transport
keeps sending `pi_envelope` frames to the **old, revoked PC epk** and the
relay rejects every one:

```
17:13:53  pi_envelope not_authorized from=i6lDEeU= to_pc_tail=l2X/dUc= room=main env_id_tail=694f2133
17:17:57  pi_envelope not_authorized ... de9318a8
17:20:33  ... 2384855e
17:22:33  ... ffdc00d1
17:24:33  ... 9589b79e
17:26:33  ... 66b1c337
...continues every ~2 min indefinitely
```

- `i6lDEeU=` = this PC's **new** epk (`13/e5m0…Ai6lDEeU=`, Owner `SBWY…`).
- `l2X/dUc=` = this PC's **prior** epk (`DXdj…dUc=`) — the sibling identity
  it held under the 5 revoked Owners. No longer a member of the current mesh.
- The relay's `is_authorized()` (`relay/src/handlers/pi_forward.rs:163`)
  correctly rejects: the new mesh (`mesh.db` owner_pk_hash
  `51aedf76…`, version 1) lists exactly one member — `i6lDEeU=` — so `i6lDEeU=`
  is **not** authorized to send to `l2X/dUc=` (different member set; the old
  epk isn't a co-member).

The frames are paired (two `env_id_tail`s per burst, ~2 min apart), which
looks like a **replay/delivery queue** retrying against the dead sibling.

## Root cause (VERIFIED 2026-07-13 against `pi-extension/src`)

The original hypothesis was close but imprecise. The sibling cache
(`BrokerRemote.siblingByLabel` / `siblingByPubkey`) **is** evicted on
`setSiblings` — that method clears and rebuilds the maps
(`broker_remote.ts:219-237`). And `setSiblings` **is** wired to fire on
membership changes: `SelfRevoke.onMembersChanged` →
`pairing_coordinator.ts:568` → `this.deps.setSiblings(siblings)`. So the
eviction mechanism exists and is wired.

The bug is a **stale-state leak in `SelfRevoke.membersByOwner`**
(`self_revoke.ts:106`). `membersByOwner` is a `Map<ownerEpk, members[]>`
that captures each Owner's member list during `_checkOwner`. It is only
ever `.set()` (line 250) — **it is never deleted from.** When an Owner
revokes this Pi:

1. Sweep N: `_checkOwner(revokedOwner)` runs. `membersByOwner.set(revokedOwner,
   newMembers)` captures the smaller list (line 250, *before* the revocation
   check). Then `stillMember` is false → `storage.removePeer(ownerEpk)`
   removes the Owner from `peers.json`, and `onRevoke` fires.
2. Sweep N+1: `listOwnerPubkeys()` reads `peers.json` — the revoked Owner is
   gone, so `_checkOwner` is **not called** for it. But `membersByOwner`
   **still holds the stale entry** from sweep N.
3. `_computeSiblingUnion()` (line 181) iterates `membersByOwner.values()` —
   **including the stale revoked-Owner entry** — so the revoked Owner's
   *other* members (the old sibling epks) persist in the sibling union
   forever.
4. `_siblingSetChanged` never sees a removal for those siblings →
   `onMembersChanged` never fires a shrink → `setSiblings` never evicts
   them → `BrokerRemote.siblingByPubkey` keeps the stale epk →
   `pi_envelope` keeps targeting it → `not_authorized` loop.

This matches the capture exactly: the old sibling epk `l2X/dUc=` (this PC's
prior epk under the 5 revoked Owners) persists because `membersByOwner`
retains the revoked Owners' member lists. A full pi restart clears it
because `membersByOwner` is in-memory (not persisted) — confirming the
workaround and the in-memory nature.

### The fix

In `_checkOwner`, after `storage.removePeer(ownerEpk)` succeeds, **delete
the Owner's entry from `membersByOwner`**:

```ts
await this.storage.removePeer(ownerEpk);
this.membersByOwner.delete(ownerEpk);  // ← the fix
if (this.onRevoke) await this.onRevoke(ownerEpk);
```

Then the next `_computeSiblingUnion` / `_siblingSetChanged` (which run at
the end of `checkOnce`, after the per-owner loop) will detect the shrinkage
and fire `onMembersChanged` → `setSiblings` evicts the stale siblings from
`BrokerRemote`. No new eviction mechanism needed — the existing one was
just being fed stale input.

### Why the existing test didn't catch it

`onMembersChanged fires when sibling set changes across sweeps`
(`self_revoke.test.ts:232`) tests sibling-set **growth** (A → A,B) across
sweeps where the Owner stays paired. It never tests the **revocation-then-
shrink** scenario (Owner revokes this Pi → its siblings must leave the
union). That's the missing coverage. The new test models exactly that:
Owner has siblings [me, A] → revoke → next sweep `listOwnerPubkeys` omits
the Owner → assert `onMembersChanged` fires with an **empty** sibling set
(A evicted), not the stale `[A]`.

## Scope (refined after verification)

- **The fix is a one-liner** in `SelfRevoke._checkOwner` (`self_revoke.ts`):
  after `storage.removePeer(ownerEpk)`, `this.membersByOwner.delete(ownerEpk)`.
  This stops the stale revoked-Owner member list from leaking into
  `_computeSiblingUnion`, so the existing `onMembersChanged` → `setSiblings`
  eviction path fires correctly.
- Add a test modeling revocation-then-shrink: Owner with siblings [me, A] →
  revoke → next sweep omits the Owner from `listOwnerPubkeys` → assert
  `onMembersChanged` fires with an empty sibling set (A evicted), not the
  stale `[A]`.
- Cross-check `relay-revocation-cache-window` (relay-side positive cache TTL)
  — that is the *relay* half of revocation convergence; this is the
  *extension* half. Both are needed for prompt revocation; they do not
  overlap. (Not in scope for this story — the extension half is the
  `membersByOwner` leak.)

## Reproduction

Already reproducing on the live VM: `docker exec outpost-pi-relay grep
pi_envelope /data/logs/relay.log.$(date -u +%F) | grep not_authorized | tail`
shows the ongoing loop. A full pi restart clears the stale in-memory peer
list (workaround), confirming the state is in-memory and not persisted.

## Acceptance

- After an Owner revocation + re-pair, the extension stops sending
  `pi_envelope` to epks not in the current mesh within one transport tick
  (no `not_authorized` loop).
- Queued envelopes targeting a revoked sibling either re-resolve to the
  sibling's new epk (if it re-paired under the same Owner) or surface a
  terminal `transport_error` to the sender.
- A unit/integration test simulating revocation mid-queue.
