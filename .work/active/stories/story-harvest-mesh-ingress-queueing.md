---
id: story-harvest-mesh-ingress-queueing
kind: story
stage: done
tags: [pi-extension, bug]
parent: feature-upstream-remote-pi-harvest
depends_on: []
release_binding: v0.7.0
gate_origin: null
created: 2026-08-15
updated: 2026-08-16
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

## Implementation

- Execution capability: sol/high for lifecycle-sensitive cross-agent delivery.
- Moved mesh ingress ownership into `SdkSessionProjection`: `agent_start` fences active runs, `agent_settled` flushes accepted ingress as one ordered custom-message batch with one `followUp` turn trigger, and lifecycle epoch invalidation clears stale-session work before its queued microtask can send.
- Admission is bounded globally and per peer by both frame count and retained UTF-8 bytes. Overflow rejects the newest frame without evicting the accepted prefix and produces content-free diagnostics; admitted messages are mirrored to owner tool timelines only after admission.
- Key files: `pi-extension/src/session/sdk_session_projection.ts`, `pi-extension/src/extension/ports.ts`, and `pi-extension/src/index.ts`, with projection regression tests and updated port fixtures.
- Verification: `corepack pnpm typecheck && corepack pnpm test && corepack pnpm build` passed (56 files, 985 passed, 3 skipped). Focused mesh/projection tests passed (51 tests).
- Deviations: upstream root-level arrays/timers were not copied; batching is one SDK custom message rather than several messages with only the last triggering, which gives the required single turn trigger and a simpler exactly-once boundary while preserving each envelope's formatted id/from/re metadata.
- Adjacent issue noted: the unrelated audit-rotation E2E cases remain timing-sensitive under full-suite load (one run observed the active file at the ceiling plus one byte; its focused rerun and the subsequent complete gate passed). No test was weakened or changed.

### Review closure

- Mesh batches remain admitted and fully accounted until SDK handoff succeeds. Synchronous throws and asynchronous non-stale rejections retain the batch for the next settled boundary; stale-context rejection evicts only that batch and its stale capability, and lifecycle epochs suppress replacement-session retries.
