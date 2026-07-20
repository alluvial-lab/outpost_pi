---
id: feature-outbound-buffer-on-peer-offline-presence-lifecycle
kind: story
stage: done
tags: [pi-extension, lifecycle]
parent: feature-outbound-buffer-on-peer-offline
depends_on: [feature-outbound-buffer-on-peer-offline-bounded-turn-buffer]
release_binding: extension-0.2.0
gate_origin: null
created: 2026-07-18
updated: 2026-07-20
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

- [x] `markPeerOnline()` drains buffered frames in original order before any
      post-resume live fan-out and handles synchronous re-entrant broadcasts.
- [x] An inbound `session_sync` from a still-marked-offline peer discards its
      buffer and resumes it before routing the authoritative sync request.
- [x] A failed `channel.send` remains isolated and does not strand the peer in
      offline/flushing state.
- [x] `detach`, relay-drop teardown, and same-peer reattach delete the old
      buffer; no frame crosses into a new `PeerChannel` lifetime.

## Implementation

Presence resume now drains the completed interval and active suffix while the
peer remains fan-out-suspended, including frames added by synchronous re-entry,
then converges the peer online even when an individual send fails. An inbound
`session_sync` discards stale buffered data before resuming and routing the
authoritative request. Detach, aggregate relay-drop teardown, and reattach clear
both buffer and offline/late-attach state.

Verification: `./node_modules/.bin/tsc --noEmit`; focused presence diagnostic
and active-turn reattach Vitest cases.
