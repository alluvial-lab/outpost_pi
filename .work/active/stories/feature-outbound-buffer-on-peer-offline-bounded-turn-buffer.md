---
id: feature-outbound-buffer-on-peer-offline-bounded-turn-buffer
kind: story
stage: drafting
tags: [pi-extension, lifecycle]
parent: feature-outbound-buffer-on-peer-offline
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-18
updated: 2026-07-18
---

# Bounded per-peer turn-interval buffer

## Brief

Implement Unit 1 from `feature-outbound-buffer-on-peer-offline`: add the
bounded, in-memory `ServerMessage` buffer owned by `OwnerMultiplexer`. This is a
design/acceptance checkpoint within the cohesive parent feature, not a separate
worker boundary.

## Files

- `pi-extension/src/extension/owner_multiplexer.ts`

## Acceptance criteria

- [ ] Offline peers buffer an independent FIFO while online peers retain the
      current immediate fan-out behavior.
- [ ] Each peer retains at most one completed interval plus its current
      interval under shared caps of 2,048 frames and 8 MiB serialized UTF-8.
- [ ] On cap pressure, the older completed interval is evicted atomically before
      the current interval is sacrificed.
- [ ] If the current interval alone crosses either cap, it is discarded in full
      and its remainder is suppressed until `completeOfflineTurn()`; no partial
      suffix flushes.
- [ ] Serialized-size accounting is non-throwing, and the next boundary permits
      a fresh interval.
