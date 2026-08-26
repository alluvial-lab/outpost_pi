---
id: backlog-relay-transport-stale-generation-active-dispatch
kind: story
stage: drafting
tags: [pi-extension, security]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-23
updated: 2026-08-26
---

# Generation-owned cancellation for in-flight relay dispatches

Surfaced by thorough review pass 6 of `feature-owner-message-e2e-authentication`
(2026-07-23) and parked as Important (below the current-cycle material bar).

## Finding

`pi-extension/src/extension/relay_transport.ts` — unbind clears queued cells and
accounting (:322-323) but the ACTIVE dispatch (raw line already copied and
awaited through the handler, :337-340; unbind at :440) is not cancelled. Each
dead reconnect generation can retain one decoded ingress object + async stack
if its handler never resolves.

## Why parked, not fixed in the feature

- Accumulation requires an indefinitely blocked handler per generation; no
  production trigger identified (storage reads complete, keyring reads are
  retry-bounded). The compound scenario (hung filesystem + relay-timed
  reconnect cycles) already implies a degraded host.
- Bounded per generation (one frame), vs the pre-feature shape (unbounded
  concurrent handlers with no tracking at all) — strictly better than before.
- The queue-side surfaces from the same review theme ARE fixed in the feature
  (bounded dispatch FIFO, control caps, generation-discard of queued work,
  bounded outbound channel queue).

## Direction when picked up

Generation-owned cancellation (AbortController-style) or a global bound on
active stale dispatches; test repeated reconnects while every prior
generation's handler remains unresolved.
