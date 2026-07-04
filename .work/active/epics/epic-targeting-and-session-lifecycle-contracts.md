---
id: epic-targeting-and-session-lifecycle-contracts
kind: epic
stage: drafting
tags: [pi-extension, app, relay, bug, docs]
parent: epic-remote-session-resilience-refactor
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-04
updated: 2026-07-04
---

# Targeting & session-lifecycle contracts (clear the contract debt the resilience refactor assumed)

## Brief

A cluster of bugs across the app↔relay↔extension surface all share one root
cause: **undefined state machines at the boundaries.** The code implements
*something* at each boundary, but no spec pins what it must be, so each surface
improvised a local decision that's wrong under an untested condition. This epic
clears that contract debt by pinning the contracts and building the
instrumentation to diagnose them — **specification surface first, not a code
rewrite** (per the `formal-rigor-stack` skill's default recommendation).

This is the work `epic-remote-session-resilience-refactor` step 3 was *supposed*
to clear: the v0.5.0 adversarial review ran without writing the contracts, and
the v0.6.0 bold-refactor scan restructured the *code* while the *contracts*
stayed unwritten. The result is that bugs in this area keep outpacing fixes —
this session alone produced three wrong fixes (a `factoryApi` re-arm, a
single-process framing, a manufactured routing leak) because each author
improvised the boundary behavior.

## Scope — three child features

### 1. Targeting & delivery contract (`feature-targeting-delivery-contract`)
Pin, in `PROTOCOL.md`, the App↔Pi data-plane targeting model that is currently
load-bearing but undocumented:
- `owner_pk` is per-machine, not per-Pi-process (the App pairs with a machine).
- `room_id` is per-`(cwd, assigned-name)`; the cwd-lock disambiguates; two
  same-named pis in one room is a lock violation, not a supported topology.
- Relay forwarding is fanout to every conn at `(owner_pk, room)` (intentional
  for multi-device owners).
- A `user_message` targets one Pi session via `session_id`.
- **Typed error codes** (operator Q1, 2026-07-04): disambiguate the single
  `session_mismatch` into `session_superseded` (your session_id is stale →
  re-sync) vs `not_my_session` (this message was for a different pi → silent
  drop). The extension can distinguish these via the session parent-chain.
  Needs wire-format work (generated protocol + app handling).

Draft in progress: `.work/drafts/draft-protocol-targeting.md` (premise
corrected — the stale error was in `#2`'s own session, NOT a cross-room leak;
the "collision conditions" section of the draft is INVALIDATED and to be deleted).

**Unblocks:** `story-foreign-session-user-message-tolerance`,
`story-fix-stale-ctx-messageapi-rearm-on-reload` (reopened).

### 2. Session-lifecycle & reconnect state-machine contract (`feature-session-lifecycle-contract`)
Pin two state machines that are currently improvised per surface:
- **Session-lifecycle** (the stale-ctx contract): when a captured SDK ctx/pi may
  be used, what invalidates it, and what tolerates the gap window on
  replacement/reload/resume/fork/daemon-respawn. Includes the canonical
  transcript-event identity contract (the live-vs-replay `eventId` collision
  root cause of `story-mobile-assistant-message-duplicated-live-replay`).
- **Reconnect** (the mobile-remote-coding skill already lists the states:
  `connected idle / working / reconnecting / offline / stale-unknown`): pin the
  transitions, who owns each state, and the rehydration contract. This is the
  upstream gap for the 2026-07-02 live-drop-test bug cluster
  (`idea-mobile-drop-slow-recovery`, `idea-mobile-drop-half-open-tcp`,
  `idea-extension-pumps-into-dead-app-peer`, `idea-mobile-outgoing-message-swallowed`,
  `idea-mobile-user-message-not-delivered-timeout`).

Output: `PROTOCOL.md` + `docs/ARCHITECTURE.md` sections + property/conformance
tests against the pinned invariants.

**Unblocks:** the reconnect bug cluster, `story-mobile-assistant-message-duplicated-live-replay`,
`idea-mobile-conflates-transport-and-agent-state`.

### 3. Integration test harness & observability (`feature-session-replacement-harness-and-observability`)
The single highest-leverage gap. Every wrong fix this session *passed its
mock-based tests* because the mocks don't model `runtime.assertActive()` or
real SDK session replacement. Deliver:
- **A session-replacement integration harness** that drives a real
  `ctx.newSession()`/`/reload`/`/resume` through the actual SDK `ExtensionRunner`
  and asserts post-replacement delivery + history + actions. Until this exists,
  every fix in this area is faith.
- **Transport-frame observability** (the parked `story-add-transport-frame-observability`)
  + **cross-side logging** (`idea-cross-side-logging-for-debug`): the
  instrumentation that makes A/B bugs diagnosable without a 30-minute source
  re-derivation. These are force-multipliers for the whole epic.

**Unblocks:** honest verification of every fix under this epic; rapid diagnosis
of future boundary bugs.

## What this epic deliberately does NOT include

- **Cluster C (ordering/steering UX bugs):** `idea-mobile-chat-reorder-on-return`,
  `idea-mobile-queued-message-does-not-reorder`,
  `idea-mobile-no-steering-indicator-when-queued`. These share a grounded
  app-side root cause (`seq`-then-`eventId` sort + no "queued" state) with NO
  contract gap — they're a real coding cluster and proceed in parallel as
  app-only work, not under this epic.
- **UX affordances & relay/security policy:** `idea-mobile-restart-pi-session-affordance`,
  `idea-mobile-session-control`, `idea-mobile-no-stop-button-while-awaiting-tool`,
  `idea-same-pc-peer-presence-ux`, `relay-mutex-poison-recovery`,
  `relay-pi-key-clone-detection`, `relay-revocation-cache-window`,
  `idea-agent-send-sandbox-egress-gate`. Each is its own design decision; not
  contract debt.
- **A code rewrite.** The contracts come first; code changes flow from them via
  the design family on each child feature.

## Existing items that fold under this epic (re-parented by reference)

Already-active items that belong here (keep their stage; re-parented via this
prose reference, not `git mv`, to preserve their history):
- `feature-session-stable-message-delivery` (implementing) + its child
  `feature-session-stable-message-delivery-stale-wake-tolerance` (done) — the
  tolerance fix; partial coverage of the session-lifecycle contract.
- `story-foreign-session-user-message-tolerance` (drafting) — blocked on the
  targeting contract (#1).
- `story-fix-stale-ctx-messageapi-rearm-on-reload` (drafting, reopened) —
  blocked on the session-lifecycle contract (#2).
- `story-fix-stale-ctx-wrapactionctx-crash` (review) — a crash guard in this
  area; folds under #2's boundary contract.
- `story-mobile-chat-blank-on-pair-after-pre-pair-work` (review) — the
  backfill fix; folds under #2's replay-identity contract.
- `story-mobile-assistant-message-duplicated-live-replay` (implementing) —
  folds under #2's canonical transcript-event identity.
- `story-add-transport-frame-observability` (drafting) — folds under #3.

## Strategic decisions

- **Spec-first, not code-first.** Pin the contracts in `PROTOCOL.md` /
  `docs/ARCHITECTURE.md` before rewriting code. Code changes flow from the
  contracts via the design family. (Per `formal-rigor-stack`: "rewrite the
  specification surface first.")
- **Contracts in `PROTOCOL.md`.** Confirmed by operator 2026-07-04: the
  targeting + session-lifecycle contracts belong in `PROTOCOL.md` (the
  data-plane authority), cross-referenced with `docs/ARCHITECTURE.md`.
- **Typed error codes over blunt tolerance.** Operator Q1, 2026-07-04:
  disambiguate `session_mismatch` into typed codes rather than treating all
  mismatches as silent re-sync. A cleaner, non-blunt answer; needs wire-format
  work scoped under feature #1.
- **The `#2` stale error is a repro-and-observe task, not a contract item.**
  Operator clarified 2026-07-04: the stale `internal_error` occurred in a
  freshly-started `#2`'s own session (not a cross-room leak). That's the
  same-session stale wake case the shipped tolerance fix should cover — the
  open question is whether the fix was live in `#2` or there's a gap. This is
  diagnosed by reproduction, NOT by inference, and is tracked separately from
  the epic (do not let it block the contract arc).

## Dependencies

- No `depends_on` on the epic itself.
- Child feature #1 (targeting) and #2 (session-lifecycle) are independent of
  each other and can be drafted in parallel.
- Child feature #3 (harness + observability) is a precondition for *honest
  verification* of #1 and #2's code changes, but not for drafting the contract
  prose — so it's `depends_on: []` for the prose and a soft dependency for
  implementation verification.

## Foundation-doc impact

This epic's *output* is primarily foundation-doc impact: new `PROTOCOL.md`
targeting + session-lifecycle sections, and `docs/ARCHITECTURE.md` state-machine
sections. Rolling-foundation: write current-state, no history prose.

## Next

`/agile-workflow:feature-design` on each child feature (#1 and #2 can run in
parallel; #3 alongside). The draft at `.work/drafts/draft-protocol-targeting.md`
is the seed for #1's contract prose (after the invalidated collision section is
removed and the real shape is confirmed via repro).
