---
id: feature-contract-gap-audit
kind: feature
stage: drafting
tags: [pi-extension, app, relay, docs]
parent: epic-targeting-and-session-lifecycle-contracts
depends_on:
  - feature-cross-side-observability
  - feature-reconnect-reproduction
release_binding: null
gate_origin: null
created: 2026-07-04
updated: 2026-07-04
---

# Contract gap audit (evidence-sourced, downstream of reproduction)

## Brief

**Demoted and renamed** from the original "targeting & delivery contract" and
"session-lifecycle contract" features. The 2026-07-04 adversarial review
showed that the original contract-first framing (a) over-aggregated confirmed
code defects and unreproduced hypotheses, (b) duplicated work already
shipped by the released bold-refactor epics, and (c) risked canonizing
unverified assumptions as current-state truth. This feature is now a narrow,
evidence-sourced **audit** that consumes/amends the released bold outputs and
harvests invariants from already-fixed stories — NOT a parallel
contract-design pass.

## Scope

### A. Targeting facts missing from `PROTOCOL.md`
`docs/ARCHITECTURE.md` already pins canonical `session_id`, relay-opaque
routing, room-targeted cross-PC, and fail-closed app session gates. The
genuine gap is narrower than the original draft claimed:
- `owner_pk` is per-machine, not per-Pi-process (the App pairs with a machine).
- `room_id` is per-`(cwd, assigned-name)`; the cwd-lock disambiguates; two
  same-named pis in one room is a lock violation, not a supported topology.
- Relay forwarding is fanout to every conn at `(owner_pk, room)` (intentional
  for multi-device owners).
- A `user_message` targets one Pi session via `session_id`.

Audit against code (`relay/src/peers/connections.rs:send_to_room`,
`registry.rs:30-45`, `pi-extension/src/rooms.ts`, `pairing/storage.ts`), don't
invent. Cross-reference with `docs/ARCHITECTURE.md` rather than duplicating.

### B. Typed error-code spike (feasibility, not confirmed scope)
Disambiguate the single `session_mismatch` into `session_superseded` (phone's
session_id is stale → re-sync) vs `not_my_session` (message was for a
different pi → silent drop). BUT `story-foreign-session-user-message-tolerance`
shows the extension **cannot** distinguish duplicate-delivery from legitimate
stale re-sync without cross-process sibling state. So:
- Run this as a **feasibility spike**: can the extension's session parent-chain
  distinguish "predecessor of my current session" from "unrelated session id"
  within one process? Does that suffice under multi-connection fanout?
- Tests for both cases (wrong-pi duplicate delivery does not render an error;
  legitimate stale session still triggers re-sync) gate any wire change.
- If parent-chain/sibling state is unavailable, prefer an app-side handling
  rule scoped to `user_message` replies plus `session_sync` behavior rather
  than a premature wire change.

### C. Session-lifecycle / transcript-identity invariants (harvested after review)
Harvest from already-fixed stories **after** their review lands — record the
discovered invariant, don't pre-write it:
- `story-fix-stale-ctx-wrapactionctx-crash` (review) — the "unguarded SDK
  getter read on stale ctx" anti-pattern becomes a contract rule.
- `story-mobile-chat-blank-on-pair-after-pre-pair-work` (review) — the "SDK is
  the durable owner; the log is the replay source; backfill on resume"
  invariant.
- `story-mobile-assistant-message-duplicated-live-replay` (implementing) — the
  canonical transcript-event identity contract (one assistant-message identity
  stable across live and replay paths). The story's root cause (random-uuid
  live vs deterministic replay eventIds + fire-and-forget `ToolRequest`
  re-flush) is a transcript-identity fix + wire change the story already
  specifies; the contract records the resulting identity rule.

### D. SDK stale-context seam (from the harness, not prose)
`story-fix-stale-ctx-messageapi-rearm-on-reload` is blocked on an SDK
architectural seam: only `ReplacedSessionContext` carries a working
`sendUserMessage`; plain `session_start` ctx does not. Contract prose can
document "captured ctx is invalid after replacement" (already in
`docs/ARCHITECTURE.md` lifecycle invariants), but it cannot answer how to
reacquire a live delivery surface after plain `session_start`. That question
is answered by the harness in `feature-cross-side-observability`; the
contract records the discovered seam after the spike, not before.

### E. `docs/ARCHITECTURE.md` bold-DAG drift
`docs/ARCHITECTURE.md` calls the bold refactor DAG "in-flight," but the four
overlapping epics are `stage: done` in `.work/releases/v0.6.0/`. Rewrite that
section current-state (rolling-foundation) as part of this audit.

## Unblocks

- `story-foreign-session-user-message-tolerance` — after the typed-error spike.
- `story-fix-stale-ctx-messageapi-rearm-on-reload` — after the harness answers
  the SDK-seam question.

## Out of scope

- The observability infrastructure (`feature-cross-side-observability`).
- The reconnect cluster attribution (`feature-reconnect-reproduction`).
- Re-designing what the released bold epics already shipped — consume/amend,
  not duplicate.
- The `#2` stale-error repro (separate observe-and-diagnose task).

## Open decisions (gated on reproduction)

- Typed-error-code names and whether the wire change is feasible at all (spike).
- Whether `session_started_at` semantics need reconciling (extension reports
  relay-start time via `ensureSessionStarted`, not real session start) — a
  secondary fix surfaced by the backfill story.

## Seed material

`.work/drafts/draft-protocol-targeting.md` — retained as background for the
targeting audit. The "collision conditions" section is INVALIDATED per
operator Q2 (no cross-room collision occurred; the stale error was in `#2`'s
own session) and is to be deleted once the real shape is confirmed via repro.
