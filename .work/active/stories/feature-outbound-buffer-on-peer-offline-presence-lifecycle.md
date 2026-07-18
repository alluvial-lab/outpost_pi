---
id: feature-outbound-buffer-on-peer-offline-presence-lifecycle
kind: story
stage: drafting
tags: [pi-extension, lifecycle]
parent: feature-outbound-buffer-on-peer-offline
depends_on: [feature-outbound-buffer-on-peer-offline-bounded-turn-buffer]
release_binding: null
gate_origin: null
created: 2026-07-18
updated: 2026-07-18
---

# Reconnect arbitration and channel-lifetime cleanup

## Brief

Implement Unit 2 from `feature-outbound-buffer-on-peer-offline`: drain the
per-peer FIFO on presence resume, make sync-first reconnects choose the
authoritative history path, and bind buffer cleanup to the managed channel
lifetime.

## Files

- `pi-extension/src/extension/owner_multiplexer.ts`

## Acceptance criteria

- [ ] `markPeerOnline()` drains buffered frames in original order before any
      post-resume live fan-out and handles synchronous re-entrant broadcasts.
- [ ] An inbound `session_sync` from a still-marked-offline peer discards its
      buffer and resumes it before routing the authoritative sync request.
- [ ] A failed `channel.send` remains isolated and does not strand the peer in
      offline/flushing state.
- [ ] `detach`, relay-drop teardown, and same-peer reattach delete the old
      buffer; no frame crosses into a new `PeerChannel` lifetime.
