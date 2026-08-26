---
id: backlog-relay-transport-stale-generation-active-dispatch
kind: story
stage: done
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

## Implementation notes
- Execution capability: inline current-session implementation; lifecycle-sensitive relay dispatch cancellation with a repeated-generation regression.
- Review weight: standard (source: caller default); bounded inline review follows green owning verification.
- Files changed: `pi-extension/src/extension/relay_transport.ts`, `pi-extension/src/extension/ports.ts`, `pi-extension/src/index.ts`, `pi-extension/src/extension/owner_multiplexer.ts`, `pi-extension/src/extension/relay_transport.test.ts`.
- Tests added/removed: repeated relay replacement with deliberately unresolved active handlers; every stale generation receives an abort signal and stop aborts the final generation.
- Simplification: used one per-binding `AbortController` shared by data/control dispatch rather than adding a second stale-work queue or global retry policy.
- Discrepancies from design: chose cooperative generation-owned cancellation over a global stale-dispatch cap; transport releases retained cells immediately while production owner handling fences side effects at async boundaries.
- Adjacent issues parked: none.
- Parallel-work collision: a later fresh-session lifecycle worker modified `pi-extension/src/index.ts` and E2E host support after this story's commit; the files were not staged or overwritten. The dirty index change is disjoint from the signal edits and is left for that worker.
- Verification: `corepack pnpm typecheck`; `corepack pnpm test` (60 files, 1102 passed, 3 skipped); `corepack pnpm build`; targeted relay transport suite (22 passed).
- Bounded inline review: pass; each relay binding owns one abort controller, unbind aborts before releasing active accounting, stale fanout is suppressed, and owner reattach checks the signal after awaited gates. No material blockers.
