---
id: feature-session-replacement-harness-and-observability
kind: feature
stage: drafting
tags: [pi-extension, app, testing, observability]
parent: epic-targeting-and-session-lifecycle-contracts
depends_on: []
release_binding: v0.1.0
gate_origin: null
created: 2026-07-04
updated: 2026-07-04
---
status: superseded
superseded_by: feature-cross-side-observability
superseded_date: 2026-07-04
---

> **SUPERSEDED 2026-07-04.** Promoted and renamed to `feature-cross-side-observability`
> (now the critical-path lead feature) under the reframed
> `epic-targeting-and-session-lifecycle-contracts`. See
> `.work/reviews/review-epic-targeting-and-session-lifecycle-contracts-2026-07-04.md`.

# Session-replacement integration harness & boundary observability

## Brief

The single highest-leverage gap in this area. Every wrong fix this session
(the `factoryApi` re-arm, the single-process framing) *passed its mock-based
tests* because the mocks don't model `runtime.assertActive()` or real SDK
session replacement. Until a real `ctx.newSession()`/`/reload`/`/resume` drives
post-replacement delivery in a test, every fix in this area is faith. This
feature delivers the harness + the observability that makes boundary bugs
diagnosable.

## Scope

1. **Session-replacement integration harness** — a test that drives a real
   `ctx.newSession()` (and `/reload`, `/resume`, fork) through the actual SDK
   `ExtensionRunner` and asserts post-replacement: message delivery works,
   history replays, app actions land on the fresh ctx, no stale-ctx throw
   reaches the wire. This is the non-negotiable verification surface for the
   whole epic. If the harness is genuinely infeasible against the installed
   SDK, document exactly why and ship an honest xfail + the observability below
   as the diagnostic substitute.
2. **Transport-frame observability** — the parked
   `story-add-transport-frame-observability`: privacy-safe, throttled
   diagnostic surface for dropped/malformed relay and peer-channel frames.
3. **Cross-side logging** — `idea-cross-side-logging-for-debug`: retroactive
   phone-side log capture so a live symptom maps back to the
   app/extension/relay path that produced it without a 30-minute source
   re-derivation.

## Why this is a feature, not a story

The harness is design-bearing — building it against the installed SDK requires
figuring out how to drive the real `ExtensionRunner` from a test, which is
non-trivial and may surface SDK constraints. The observability items each have
open design decisions (what's release-visible without leaking payloads, log
retention/rotation on mobile). All three are force-multipliers for the epic,
not one-line fixes.

## Unblocks

- Honest verification of every code fix under
  `epic-targeting-and-session-lifecycle-contracts`.
- Rapid diagnosis of future boundary bugs (the instrumentation that would have
  caught this session's wrong premises earlier).

## Out of scope

- The contract prose (features #1/#2).
- The `#2` stale-error repro (separate observe-and-diagnose task).

## Open decisions (design time)

- Harness feasibility: can the installed SDK's `ExtensionRunner` be driven
  headless from a vitest? If not, what's the minimal real-SDK seam?
- Observability: what's release-safe to surface (counts vs structured events
  vs debug-mode-only), and the throttling/retention policy.
