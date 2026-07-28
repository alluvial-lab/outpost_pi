---
id: epic-targeting-and-session-lifecycle-contracts
kind: epic
stage: done
tags: [pi-extension, app, relay, bug, docs, observability]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-04
updated: 2026-07-19
reframed: 2026-07-04
---

# Boundary observability & contract gap audit (clear the observability debt that masquerades as contract debt)

## Brief

A cluster of bugs across the app↔relay↔extension surface **look like** they
share one root cause — "undefined state machines at the boundaries" — but the
2026-07-04 adversarial review (`.work/reviews/review-epic-targeting-and-session-lifecycle-contracts-2026-07-04.md`)
showed that framing over-aggregates confirmed code defects, SDK seam
constraints, and **unreproduced** hypotheses under one banner. The actual
shared root cause is narrower and more operational:

> **We are observability-blind on the side where these bugs manifest.**

The extension side is already retroactively diagnosable (`audit.jsonl`,
append-only, survives reboots). The phone side is not — only `debugPrint` →
logcat ring buffer (bounded, wiped on reboot, rolled over). The relay is not —
stdout only. So every intermittent mobile bug noticed after the fact
(reconnect cluster, swallowed messages, no-echo timeouts, stale-ctx throws) is
**anecdotal** on the phone: by the time it's noticed, the logcat is gone.

The operator opened this epic to see if a foundational issue was contributing
to the bug class. The foundational issue is real, but it is **observability
debt**, not contract debt. Contracts written now would either (a) re-document
truth already pinned by the released bold-refactor epics
(`epic-bold-canonical-session`, `epic-bold-reachability-contract`,
`epic-bold-transcript-event-log`, `epic-bold-turn-state-machine` — all
`stage: done` in `.work/releases/v0.6.0/`), or (b) canonize unverified
assumptions as current-state truth (the draft contract's "collision
conditions" premise was already invalidated once by the operator's Q2
clarification — exactly the failure mode current-state docs must avoid).

**Reframe:** make observability + reproduction the first-class critical path,
and demote contract prose to an **evidence-sourced gap audit** that runs
*after* reproduction makes the actual bugs visible. Most of the speculative
contract work will turn out not to be contract debt at all.

## Scope — three child features (reordered)

### 1. Cross-side observability & reproduction (`feature-cross-side-observability`) — CRITICAL PATH
**Promoted from the old feature #3.** This is the unlock for the whole epic.
Deliver, in priority order:
- **Phone-side persistent ring log** (`idea-cross-side-logging-for-debug`,
  2026-06-29 survey): a bounded in-memory ring buffer flushed to a file on
  device (`getApplicationDocumentsDirectory`) + an in-app "Export debug log"
  share-sheet action. This is the single highest-leverage piece — it converts
  the entire reconnect cluster from "anecdotal" to "diagnosable after the
  fact." `adb logcat -d` remains the zero-setup USB path; the ring log covers
  the non-USB / reboot / buffer-rollover case.
- **Cross-side correlation key:** the message id already shared between app
  (`[msg-send] id=…`) and extension (`app user_message id=…`). Extend it onto
  the relay forward path (`pi_forward`) so one id greps across all three
  sides.
- **Relay persistent logging:** optional file sink for `tracing` (stdout
  remains default; gate the file sink behind an env flag / container volume).
  Today the relay's stdout is gone on scroll/restart unless the operator
  redirected at launch — making the relay side match the extension's
  retroactive capability.
- **Transport-frame observability** (`story-add-transport-frame-observability`,
  parked): privacy-safe, throttled diagnostic surface for dropped/malformed
  relay and peer-channel frames.
- **Session-replacement integration harness** (the old "harness" half of
  feature #3): drives a real `ctx.newSession()`/`/reload`/`/resume` through
  the actual SDK `ExtensionRunner` and asserts post-replacement delivery +
  history + actions. This is the **test-side analog** of the ring log — it
  makes the mock-only failures (`messageApi` re-arm) reproducible in CI
  instead of only in live use. Same disease (can't observe real replacement),
  different surface. If genuinely infeasible against the installed SDK,
  document exactly why and ship an honest xfail + the ring log as the
  diagnostic substitute.

**Unblocks:** honest verification of every code fix under this epic; rapid
diagnosis of future boundary bugs; attribution of the reconnect cluster.

### 2. Reconnect reproduction & attribution (`feature-reconnect-reproduction`) — OBSERVATION WORKSTREAM
Split out from the old "session-lifecycle contract" feature. These bugs are
**observation gaps, not design gaps** — most are explicitly unreproduced:
- `idea-mobile-drop-slow-recovery` (unconfirmed contributors; needs phone-side timing).
- `idea-mobile-drop-half-open-tcp` (duplicate-auth cleanup confirmation).
- `idea-extension-pumps-into-dead-app-peer` (`peer_offline` emission/consumption unconfirmed).
- `idea-mobile-outgoing-message-swallowed` (not reproduced server-side).
- `idea-mobile-user-message-not-delivered-timeout` (hypothetical echo-drop).

**Do not pin a reconnect state machine in foundation docs from assumed
behavior.** The mobile-remote-coding skill lists target states
(`connected idle / working / reconnecting / offline / stale-unknown`); those
are the *target*, but the contract should be updated **after** the trace
tells which state machine is wrong (app backoff, relay duplicate-connection
cleanup, extension peer-offline consumption, send queue, or UI projection).
This feature **feeds** the contract rather than being blocked-on or
unblocked-by it. Blocked on feature #1's ring log + relay logging.

### 3. Contract gap audit (verified) (`feature-contract-gap-audit`) — DOWNSTREAM
**Demoted and renamed.** A narrow, evidence-sourced audit against the
released bold-refactor outputs, NOT a parallel contract-design pass. Two
sub-tracks, both gated on reproduction evidence from #1/#2:
- **Targeting facts already missing from `PROTOCOL.md`.** `docs/ARCHITECTURE.md`
  already pins canonical `session_id`, relay-opaque routing, room-targeted
  cross-PC, and fail-closed app session gates. The genuine gap is narrower
  than the original draft claimed: App↔Pi pairing/room-derivation/fanout
  semantics and the `owner_pk` (per-machine) / `room_id` (per-`(cwd,
  assigned-name)`) facts. Audit, don't invent.
- **Typed error-code spike** (`session_superseded` vs `not_my_session`): the
  foreign-session story shows the extension **cannot** distinguish
  duplicate-delivery from legitimate stale re-sync without cross-process
  sibling state. Make this a feasibility spike with tests for both cases, not
  a confirmed wire change. If parent-chain/sibling state is unavailable,
  prefer an app-side handling rule scoped to `user_message` replies.
- **Session-lifecycle / transcript-identity invariants:** harvest from
  already-fixed stories (`story-fix-stale-ctx-wrapactionctx-crash`,
  `story-mobile-chat-blank-on-pair-after-pre-pair-work`,
  `story-mobile-assistant-message-duplicated-live-replay`) **after** their
  review lands — record the discovered invariant, don't pre-write it. The
  duplication bug's root cause (random-uuid live vs deterministic replay
  eventIds + fire-and-forget `ToolRequest` re-flush) is a transcript-identity
  fix + wire change the story already specifies, not blocked on contract prose.

**Unblocks:** `story-foreign-session-user-message-tolerance` (after the
typed-error spike), `story-fix-stale-ctx-messageapi-rearm-on-reload`
(after the harness answers the SDK-seam question).

## What this epic deliberately does NOT include

- **Cluster C (ordering/steering UX bugs):** `idea-mobile-chat-reorder-on-return`,
  `idea-mobile-queued-message-does-not-reorder`,
  `idea-mobile-no-steering-indicator-when-queued`. Grounded app-side root cause
  (`seq`-then-`eventId` sort + no "queued" state) with NO contract gap —
  app-only work in parallel.
- **`idea-mobile-conflates-transport-and-agent-state`:** misfiled under the old
  "reconnect contract." Its own analysis shows the domain model
  (`AppTurnStatus`) is already correct and the gap is the UI projection
  flattening two axes. Route under turn-state/UI projection work (consumes
  released `epic-bold-turn-state-machine`), not this epic.
- **UX affordances & relay/security policy:** `idea-mobile-restart-pi-session-affordance`,
  `idea-mobile-session-control`, `idea-mobile-no-stop-button-while-awaiting-tool`,
  `idea-same-pc-peer-presence-ux`, `relay-mutex-poison-recovery`,
  `relay-pi-key-clone-detection`, `relay-revocation-cache-window`,
  `idea-agent-send-sandbox-egress-gate`. Each its own design decision; not
  observability debt.
- **A code rewrite.** Observability + reproduction first; code changes flow
  from what reproduction finds, via the design family on each child feature.

## Existing items that fold under this epic (re-parented by reference)

- `feature-session-stable-message-delivery` (implementing) + child
  `feature-session-stable-message-delivery-stale-wake-tolerance` (done) — the
  tolerance fix; partial coverage of the session-lifecycle invariant.
- `story-foreign-session-user-message-tolerance` (drafting) — blocked on the
  typed-error spike (feature #3).
- `story-fix-stale-ctx-messageapi-rearm-on-reload` (drafting, reopened) —
  blocked on the harness (feature #1) answering the SDK-seam question.
- `story-fix-stale-ctx-wrapactionctx-crash` (review) — crash guard; harvests
  invariant into feature #3 after review.
- `story-mobile-chat-blank-on-pair-after-pre-pair-work` (review) — backfill
  fix; harvests invariant into feature #3 after review.
- `story-mobile-assistant-message-duplicated-live-replay` (implementing) —
  transcript-identity fix; harvests invariant into feature #3.
- `story-add-transport-frame-observability` (drafting) — folds under feature #1.
- `idea-cross-side-logging-for-debug` (backlog) — promoted to the lead child
  of feature #1.

## Relationship to the released bold refactor DAG

`docs/ARCHITECTURE.md` currently calls the bold refactor DAG "in-flight," but
the four epics this area overlaps are all `stage: done` in
`.work/releases/v0.6.0/`:
- `epic-bold-canonical-session` — canonical `session_id` on every chat-bearing
  message; relay routes to `(to_pc, to_room)` opaquely; endpoints validate
  fail-closed. (Overlaps the old targeting contract.)
- `epic-bold-transcript-event-log` — `TranscriptEvent` canonical; hydration is
  replay, not replace. (Overlaps transcript-identity.)
- `epic-bold-reachability-contract` — one `Reachability` state machine
  (`Connecting / Online / Degraded / Offline / Retrying` + one backoff policy).
  (Overlaps the old reconnect contract.)
- `epic-bold-turn-state-machine` — algebraic `Turn` lifecycle replacing
  smeared booleans. (Overlaps turn/working convergence.)

**This epic does NOT design parallel contracts.** Feature #3 is an audit that
consumes/amends the released bold outputs. The `docs/ARCHITECTURE.md`
"in-flight" wording is itself doc drift to fix as part of feature #3's gap
audit (rolling-foundation: rewrite current-state in place).

## Strategic decisions

- **Observability-first, not spec-first.** The `formal-rigor-stack` "rewrite
  the specification surface first" default targets *rigorous reimplementation*;
  this is contract-pinning on an existing, working system, and the actual
  bottleneck is reproduction, not prose. (Per the 2026-07-04 review's central
  question: this epic pins only verified current-state contracts and routes
  everything else through observability/reproduction first.)
- **Contracts in `PROTOCOL.md` / `docs/ARCHITECTURE.md` — but evidence-sourced.**
  Every foundation-doc claim carries an evidence source: code path, passing
  test, live reproduction, or released work item. No pinning of unverified
  assumptions as current-state truth.
- **Typed error codes are a spike, not a confirmed scope item.** Feasibility
  depends on whether the extension can distinguish the two cases; tests for
  both cases gate any wire change.
- **The `#2` stale error is a repro-and-observe task.** Operator Q2: the stale
  `internal_error` occurred in a freshly-started `#2`'s own session, not a
  cross-room leak. Diagnosed by reproduction (does the shipped tolerance fix
  cover it?), NOT by inference. The ring log (feature #1) is what makes this
  reproducible instead of anecdotal.

## Epic-design run note (2026-07-18)

Delegated by an active agile-workflow autopilot goal for `--all` (all active work). Resolve ambiguities with judgment, log rationale in the item body, and do not ask strategic questions unless a hard halt condition applies. Worker capability for this run: `openai-codex/gpt-5.6-sol` (thinking high) — selected because the ready work is security-critical, cross-stack, and contract-bearing; use it for any sub-dispatch and do not re-ask. Review weight for this run: `standard` (source: default); pass it unchanged to feature review and final completion review. Apply the risk-driven advisory policy from `principles/SKILL.md` Part IV. Treat reviewer findings as proposals: independently adjudicate them against repository context, fix or activate only material current-cycle blockers, and park valid lower-risk work in the unbound backlog.

This pass used direct repository reads plus `work-view` graph checks. Design-time
advisory review was skipped because the operator had already fixed the exact
three-feature shape and this pass only normalized ownership, dependency status,
and stage metadata; no product or external-contract choice remained open.

## Decomposition (confirmed 2026-07-18)

Decomposition pre-existed — 3 child features, listed below. The operator's
observability-first reframe already established a coherent capability chain,
so this epic-design pass normalized the existing graph rather than creating or
redesigning children. The chain deliberately makes evidence capture precede
reproduction, and reproduction precede contract claims.

### Child features

- `feature-cross-side-observability` — phone, relay, and extension diagnostics
  plus session-replacement reproduction — depends on: `[]` — **DONE and
  shipped in `.work/releases/v0.1.0/`.**
- `feature-reconnect-reproduction` — reproduce and attribute the remaining
  live reconnect/drop observations — depends on:
  `[feature-cross-side-observability]` — **READY** because its dependency is
  terminal.
- `feature-contract-gap-audit` — harvest only verified targeting, lifecycle,
  and transcript invariants — depends on:
  `[feature-cross-side-observability, feature-reconnect-reproduction]` —
  **BLOCKED on `feature-reconnect-reproduction`**; the observability dependency
  is already terminal.

The two live-repro checkpoints left under the now-terminal
`feature-mobile-tui-parity-chat-resilience` are re-parented to
`feature-reconnect-reproduction`: `idea-mobile-drop-slow-recovery` and
`idea-mobile-outgoing-message-swallowed`. This follows the epic's existing
scope and gives the unresolved observations an active owner without changing
their parked, evidence-first disposition.

### Simplification arcs

- `feature-reconnect-reproduction` separates attributed code defects from real
  contract gaps instead of expanding a speculative reconnect contract.
- `feature-contract-gap-audit` amends released canonical contracts from
  evidence rather than creating a parallel specification surface.

### Decomposition risks

- The two remaining live-repro stories require a physical phone and real
  wifi↔cellular/WireGuard transitions; keep them parked until evidence exists
  rather than tuning reconnect behavior from anecdotes.
- The downstream audit must remain evidence-sourced. Treating target states as
  current behavior would recreate the aggregation failure that caused the
  observability-first reframe.

## Next

Run `/agile-workflow:feature-design` on `feature-reconnect-reproduction`.
`feature-contract-gap-audit` becomes ready only after that feature completes.
The draft at `.work/drafts/draft-protocol-targeting.md` remains background for
the later audit; its collision section is invalidated per operator Q2.

## Review provenance

Reframed 2026-07-04 from the original "targeting & session-lifecycle
contracts" framing after the adversarial review at
`.work/reviews/review-epic-targeting-and-session-lifecycle-contracts-2026-07-04.md`
(verdict: REFRAME BEFORE PROCEEDING). The original framing over-aggregated
confirmed code defects, SDK seam constraints, and unreproduced hypotheses
under "undefined state machines"; the operator's framing — that the bug class
exists because productions/reproductions can't be captured on the app side
except anecdotally — is the actual root cause and drives the observability-first
reorder.

## Retirement (2026-07-28)

Closed. The epic's reframe thesis — that the bug cluster was observability
debt, not contract debt — self-executed:

- **Feature #1 (cross-side-observability): shipped** (v0.1.0). The phone-side
  ring log + export, relay persistent logging, transport-frame observability,
  and session-replacement harness all landed. This unlocked retroactive
  diagnosis of the whole cluster.
- **Feature #2 (feature-reconnect-reproduction): ran its course.** The
  observability unlock resolved 3 of 5 cluster bugs
  (`idea-extension-pumps-into-dead-app-peer`,
  `idea-mobile-user-message-not-delivered-timeout`,
  `idea-mobile-drop-half-open-tcp`) and left 2 as unreproduced-with-
  instrumentation (`idea-mobile-drop-slow-recovery`,
  `idea-mobile-outgoing-message-swallowed`) — no recurrence in 3+ weeks.
- **Feature #3 (contract-gap-audit): dissolved.** The contract prose audit
  (`story-reconnect-derived-contract-claims-audit`) had nothing to audit
  that wasn't already documented by the released bold-refactor epics
  (`epic-bold-canonical-session`, `epic-bold-reachability-contract`,
  `epic-bold-transcript-event-log`, `epic-bold-turn-state-machine`).

The 2026-07-27 live observation `story-mobile-transcript-reorder-after-backlog-flush`
was promoted to standalone (it is a fresh, concrete repro, not residue of
this epic). The epic body is retained here in archive for provenance.
