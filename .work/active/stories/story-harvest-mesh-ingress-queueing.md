---
id: story-harvest-mesh-ingress-queueing
kind: story
stage: implementing
tags: [pi-extension, bug]
parent: feature-upstream-remote-pi-harvest
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-15
updated: 2026-08-15
---

# Queue Pi-to-Pi mesh messages between agent runs

Upstream `56a73d9d` (queue mesh messages while busy): when a mesh message
arrives mid-run, ours drops it if `_pi` is absent and otherwise fires
`triggerTurn:true` immediately (`pi-extension/src/index.ts:2148-2178`) —
mid-turn delivery can wedge or lose the message. The owner-channel
outbound-delivery queue from our observability arc does NOT cover Pi-to-Pi
mesh ingress (different path).

## Direction

Port the queue-and-batch shape: mesh ingress during an active run is
buffered per-peer and flushed at run end (`agent_settled` boundary — same
fence the hot-reload restart wrapper uses), then delivered as a single
turn trigger. Integrate with `SdkSessionProjection` lifecycle
(`sdk_session_projection.ts`) rather than upstream's root-level index state
(they queue at their `index.ts:809,3631-3667`); respect the frame-byte
bounded-admission pattern (`.agents/skills/patterns/
frame-byte-bounded-admission.md`) for the buffer, and the
generation-fenced-async-ownership pattern so a replaced session's flush is
suppressed.

## Verification

`corepack pnpm typecheck && corepack pnpm test && corepack pnpm build`;
tests: message arriving mid-run is delivered exactly once after settle;
buffer bound enforced; stale-session flush suppressed. Cite upstream sha.
