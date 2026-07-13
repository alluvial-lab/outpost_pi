---
id: story-extension-stale-sibling-evict-on-owner-revocation
kind: story
stage: drafting
tags: [pi-extension, bug, lifecycle, security]
parent: epic-targeting-and-session-lifecycle-contracts
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-12
updated: 2026-07-12
root_cause_confirmed: 2026-07-12
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

## Root cause (preliminary — to confirm in `pi-extension/src`)

The cross-PC agent-mesh transport holds an **in-memory peer/sibling list**
plus a **delivery/replay queue** keyed by sibling epk. On Owner revocation +
re-pair, neither is evicted:

1. The stale sibling epk `DXdj…dUc=` remains in the peer list.
2. Any queued outbound `pi_envelope`s targeting it are not drained/cancelled.
3. The transport keeps retrying them every ~2 min, each hitting `not_authorized`.

This is adjacent to — but distinct from — `story-to-room-sender-side-room-
targeting` (which fixes the `to_room: "main"` default so cross-PC envelopes
reach a *live* sibling room). That story makes delivery work for **current**
siblings; this story makes the transport **stop** targeting siblings that no
longer exist.

## Scope

- Locate the cross-PC transport's sibling peer cache and delivery/replay
  queue in `pi-extension/src` (likely `transport/peer_channel.ts`,
  `transport/broker_remote.ts`, or the mesh module).
- On Owner revocation / mesh-version advance / re-pair, **evict** any sibling
  epk no longer present in the new mesh's member list, and **drain/cancel**
  queued envelopes targeting evicted siblings (surface a terminal
  transport_error to the sender rather than infinite retry).
- Cross-check `relay-revocation-cache-window` (relay-side positive cache TTL)
  — that is the *relay* half of revocation convergence; this is the
  *extension* half. Both are needed for prompt revocation; they do not
  overlap.

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
