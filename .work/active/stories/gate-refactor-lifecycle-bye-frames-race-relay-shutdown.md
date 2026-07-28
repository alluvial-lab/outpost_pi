---
id: gate-refactor-lifecycle-bye-frames-race-relay-shutdown
kind: story
stage: implementing
tags: [pi-extension]
parent: feature-lifecycle-disposal-async-void
depends_on: []
release_binding: null
gate_origin: refactor
created: 2026-07-24
updated: 2026-07-28
---

# Secure-channel bye frames race relay shutdown

## Source
gate-refactor scan for v0.3.0 (2026-07-24) — library `lifecycle`, rule `unguarded-async-void`, confidence Medium → parked per gate_finding_routing / ambient rule.

## Location
`pi-extension/src/index.ts:943`

## Issue
_goIdle enqueues protected bye frames, immediately detaches all channels, and closes the relay without awaiting each secure channel's persistence/send drain.

## Fix
Make teardown awaitable, detach each owner with the bye reason, await returned whenIdle work, and only then stop the relay.

## Design checkpoint
- Change `_goIdle(byeReason?: ByeReason)` to `Promise<void>` and propagate the async stop contract through `RelayTransportPort`, composition-root shutdown, `LocalMeshCommands`, and `ControlCommands`.
- Replace broadcast-plus-`detachAll` with one `detach(peerId, byeReason)` per snapshotted owner. Await all returned drains with `Promise.allSettled` before `_relayTransport.stop`; one failed drain cannot block global teardown.
- Coalesce overlapping stop requests behind one in-flight promise.
- Keep `SecurePeerChannel.whenIdle()` relay-independent: local sequence persistence, synchronous WebSocket enqueue, accepted ingress, and audit drain only—never a relay ACK, future relay frame, or close.
- Preserve the `8b987c8` working-state convergence before relay close.

## Acceptance evidence
- A deterministic persistence barrier proves relay close does not occur until the protected bye has drained.
- Multi-owner teardown sends exactly one reasoned bye/detach per owner, and drain rejection is observed while relay close still completes.
- Concurrent stops do not duplicate teardown.
- `session_shutdown`, slash stop, control off/toggle, and rename relay cycling await the same stop promise.

## Ordering
This establishes the awaited `owners.detach` lifecycle contract consumed by `gate-refactor-lifecycle-self-revoke-discards-async-detach`.
