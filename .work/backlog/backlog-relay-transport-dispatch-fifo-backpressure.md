---
id: backlog-relay-transport-dispatch-fifo-backpressure
created: 2026-07-23
updated: 2026-07-23
tags: [pi-extension, security]
---

# Bound the relay-transport dispatch FIFO (hostile-ingress backpressure)

Surfaced by thorough review pass 3 of `feature-owner-message-e2e-authentication`
(2026-07-23) and parked as Important (pre-existing, cross-cutting, needs
drop-policy design) — the feature's own additions (owner-channel audit path)
were bounded in the same cycle; this upstream surface predates it.

## Finding

Every WebSocket message appends a promise capturing the complete raw line to a
serial dispatch FIFO (`pi-extension/src/extension/relay_transport.ts:178-186`).
Dispatch can block on asynchronous owner lookup
(`owner_multiplexer.ts:314-316` → storage read per frame when no channel is
attached). A malicious relay (or any flooding authenticated peer) can sustain
ingress faster than dispatch and grow extension memory without bound —
especially frames for detached channels or unknown peers, which never reach
the channel-level 64-frame cap (`transport/peer_channel.ts:444-448`) added in
the E2E feature. Existing flood tests inject into the channel fanout and
bypass this FIFO (`peer_channel.test.ts:112-125,153-166`).

## Why parked, not fixed in the feature

- Pre-existing structural property of the transport, not introduced by the
  owner-channel work; memory-only (drains when the flood stops; a crash is
  recoverable via daemon restart).
- A correct fix needs a drop policy that cannot harm legitimate bursts —
  reconnect replay (queued `user_message`s) and other legal traffic flow
  through the same FIFO, and silent drops there are the stuck-message defect
  class this repo has already fought.

## Direction when picked up

Bound frames AND bytes at `bindRelay.onMessage` before allocating FIFO
promises, with overflow auditing and preserved ordering; per-frame-class drop
semantics (unknown-peer junk vs known-peer legitimate burst); tests through
the real relay-transport dispatch path with a deliberately blocked handler.
