# Review: epic-targeting-and-session-lifecycle-contracts

## 1. Verdict

**REFRAME BEFORE PROCEEDING.** The epic is pointing at a real class of failures — stale SDK contexts, session-scoped routing, replay identity, reconnect hydration, and missing real-SDK tests — but its thesis over-aggregates confirmed code defects, SDK seam constraints, and unreproduced reconnect hypotheses under one “undefined state machines” banner. The highest-confidence conclusion from the files is not “write PROTOCOL.md first”; it is “the current mock/test surface is lying, and foundation docs must only pin verified current truth.” Proceed, but only after making the harness/observability and reproduce/observe work first-class critical path, splitting verified contracts from speculative designs, and reconciling this epic with the bold-refactor artifacts already released or documented.

## 2. Confirmed strengths

- The epic correctly identifies that the current fixes in this area are under-verified: it says every wrong fix passed mock-based tests and that feature #3 is required for honest verification (`.work/active/epics/epic-targeting-and-session-lifecycle-contracts.md:80`, `:157`; `.work/active/features/feature-session-replacement-harness-and-observability.md:18`, `:32`).
- The draft contract was self-correcting about a false premise: it explicitly says the `#2` stale error is directly testable, should not be inferred, and should not be spec’d until answered (`.work/drafts/draft-protocol-targeting.md:20`, `:23`, `:25`). That is the right instinct.
- The epic correctly excludes the app-only ordering/queued-message cluster instead of forcing every nearby symptom into the contract arc (`.work/active/epics/epic-targeting-and-session-lifecycle-contracts.md:100`).
- Putting verified protocol constraints in `PROTOCOL.md` and lifecycle/state-machine invariants in `docs/ARCHITECTURE.md` is directionally right for durable current-state docs; the problem is not the destination, but which claims are verified enough to pin.

## 3. Material challenges

### A. Does the root-cause framing hold?

#### A1. Duplicated assistant message: partially a contract gap, but not a session-lifecycle bottleneck

**Position: reframe.** The story’s confirmed root cause is very specific: app live events use random `uuid7()` identities while replay uses deterministic ids, and `ToolRequest` pre-tool flush is fire-and-forget, allowing repeat commits before the streaming buffer clears (`story-mobile-assistant-message-duplicated-live-replay.md:47`, `:90`, `:114`, `:140`, `:164`). That is a transcript-event identity and app lifecycle bug. A contract is useful only if it pins one canonical assistant-message identity across live and replay; a broad “session-lifecycle contract” does not itself address the double-flush or the missing stable live-frame identity.

**Evidence:** The story already specifies the winning fix shape: deterministic server/replay identity must win, live frames likely need stable identity from the extension, and `ToolRequest` flush must not re-commit an already-flushed buffer (`story-mobile-assistant-message-duplicated-live-replay.md:140`, `:164`, `:177`).

**Recommendation:** Split “canonical transcript-event identity” out of feature #2 as its own transcript contract/fix slice, tied to the existing transcript-event-log architecture. Do not treat it as blocked on a generic session-lifecycle prose pass. The bottleneck is the paired wire/app fix plus tests, not the prose label.

#### A2. Stale `messageApi` re-arm: contract prose is not load-bearing until the SDK seam is solved

**Position: challenge.** The story’s core blocker is an SDK architectural seam: the only working `sendUserMessage` is on `ReplacedSessionContext`, plain `session_start` has no `sendUserMessage`, and every cached API goes stale on replacement (`story-fix-stale-ctx-messageapi-rearm-on-reload.md:52`, `:57`, `:63`). A `PROTOCOL.md` session-lifecycle section can document “captured ctx is invalid after replacement,” but that is already present in `docs/ARCHITECTURE.md` lifecycle invariants (`docs/ARCHITECTURE.md:227`). It does not answer how to reacquire a live delivery surface after plain `session_start`.

**Evidence:** The story itself says any new fix needs an integration test through the real SDK runner because mocks do not prove `runtime.assertActive()` behavior (`story-fix-stale-ctx-messageapi-rearm-on-reload.md:95`). Feature #3 says the same thing more strongly: without a real `ctx.newSession()`/`/reload`/`/resume` test, every fix is faith (`feature-session-replacement-harness-and-observability.md:22`).

**Recommendation:** Make this a harness-backed SDK seam spike first: can the extension obtain a fresh `ReplacedSessionContext` or equivalent after plain `session_start`? Contract prose should record the discovered seam after the spike, not pretend to unblock it before the seam exists.

#### A3. Blank chat after pre-pair work: real invariant, but the story does not need the epic to proceed

**Position: reframe.** The blank-history root cause is a concrete extension-side backfill gap: `/resume` renders persisted entries to the TUI directly, does not fire `message_end`, and the process-local `TranscriptEventLog` stays empty (`story-mobile-chat-blank-on-pair-after-pre-pair-work.md:83`, `:85`, `:105`, `:106`). The confirmed fix is to backfill the `TranscriptEventLog` from `ctx.sessionManager.getEntries()` on `session_start` (`story-mobile-chat-blank-on-pair-after-pre-pair-work.md:128`, `:130`).

**Evidence:** The story is already at `stage: review` with verification and a fix shape. It also explicitly says the extension log is fed only by live SDK hooks (`story-mobile-chat-blank-on-pair-after-pre-pair-work.md:43`).

**Recommendation:** Do not fold this as blocking work under the epic. Harvest the invariant after review: “replay source must be backfilled from SDK durable session state on resume.” The code fix is the source of truth here; docs can be updated as rolling-foundation follow-through.

#### A4. `wrapActionCtx` crash: folding it under the epic is mostly relabeling

**Position: challenge.** This is a confirmed unguarded-getter crash: property accesses like `ctx.modelRegistry` happened outside try/catch and threw synchronously on stale ctx (`story-fix-stale-ctx-wrapactionctx-crash.md:46`). The fix wraps the property-access sequence and returns `null` for stale ctx, with regression tests and verification (`story-fix-stale-ctx-wrapactionctx-crash.md:59`, `:72`, `:79`).

**Recommendation:** Treat it as evidence for an implementation rule (“guard SDK getter reads behind stale-context handling”), not as a work item that needs the contract epic. It does not require new protocol semantics.

#### A5. Reconnect cluster: contract-first is premature for unreproduced or unattributed bugs

**Position: challenge.** Several reconnect items explicitly say the cause is unknown or not yet reproduced. Slow recovery has unconfirmed contributors and needs phone-side timing (`idea-mobile-drop-slow-recovery.md:26`, `:35`, `:47`). The dead-peer streaming item says relay/offline signaling to the extension was not confirmed and asks to verify whether `peer_offline` is emitted/consumed (`idea-extension-pumps-into-dead-app-peer.md:36`, `:64`). The swallowed outgoing message is not reproduced server-side (`idea-mobile-outgoing-message-swallowed.md:19`). The “not delivered” badge is a hypothesis and asks for reproduction/trace (`idea-mobile-user-message-not-delivered-timeout.md:42`, `:54`, `:57`).

**Recommendation:** Create a “reconnect observe/reproduce” workstream that feeds the contract. Do not pin a reconnect state machine in foundation docs from assumed behavior. The mobile-remote-coding skill gives a good target shape, but these bugs need attribution before they can be classified as app backoff, relay duplicate-connection cleanup, extension peer-offline consumption, send queue semantics, or UI projection.

### B. Is spec-first the right sequencing here?

#### B1. Much of the targeting/session truth is already documented; the new epic is not starting from zero

**Position: reframe.** `docs/ARCHITECTURE.md` already states core session targeting facts: canonical `session_id` on every session-scoped chat-bearing message, app fail-closed on missing/foreign IDs, relay never routes by `session_id`, and cross-PC delivery is room-targeted via required `to_room` (`docs/ARCHITECTURE.md:188`, `:191`, `:194`, `:195`, `:199`). `PROTOCOL.md` already pins cross-PC `to_room` and `bad_envelope` behavior (`PROTOCOL.md:110`, `:115`, `:116`).

**Challenge:** The epic says targeting is “load-bearing but undocumented,” but the current docs already document several of the load-bearing facts. The true gap is narrower: App↔Pi pairing/room derivation/fanout semantics and typed mismatch/error semantics.

**Recommendation:** Feature #1 should be a gap audit against existing docs and code, not a fresh contract invention pass. Explicitly separate “verified existing truth to copy into PROTOCOL.md” from “new behavior/design decision.”

#### B2. The invalidated draft is a warning against pinning before reproduction

**Position: challenge.** The draft says the stale `#2` scenario is directly testable and “Do not spec the contract until that’s answered” (`draft-protocol-targeting.md:20`, `:23`). The epic later says “do not let it block the contract arc” (`epic-targeting-and-session-lifecycle-contracts.md:150`). Those two positions are in tension.

**Recommendation:** Keep noncontroversial verified targeting facts moving, but block any contract claims derived from the `#2` stale scenario until the single-fresh-pi reproduction answers whether the tolerance fix was live or incomplete. The stale premise already caused a manufactured routing-leak theory; that is exactly the failure mode current-state docs must not canonize.

#### B3. The strongest evidence points to missing real integration tests, not missing prose

**Position: reframe.** The epic cites three wrong fixes as evidence that contracts are needed, but its own feature #3 diagnoses the sharper cause: mocks do not model `runtime.assertActive()` or real session replacement (`feature-session-replacement-harness-and-observability.md:18`, `:22`, `:32`). The `messageApi` story independently reaches the same conclusion (`story-fix-stale-ctx-messageapi-rearm-on-reload.md:95`).

**Recommendation:** Treat feature #3 as the critical path for any session-replacement code fix and for validating contentious contract language. Feature #1/#2 can draft only verified current-state prose in parallel; they should not become the justification for code changes that the harness cannot test.

### C. Scope and boundary questions

#### C1. Typed error codes are plausible but not established by the current evidence

**Position: challenge.** Feature #1 asserts the extension can distinguish `session_superseded` from `not_my_session` via a session parent-chain (`feature-targeting-delivery-contract.md:31`, `:35`). But the foreign-session story says a pi cannot distinguish duplicate delivery from legitimate stale-session re-sync from the `user_message` alone, and that sibling-aware disambiguation would require non-trivial cross-process state (`story-foreign-session-user-message-tolerance.md:42`, `:44`, `:46`, `:61`).

**Nuance:** A parent-chain could distinguish “predecessor of my current session” from “unrelated session id” inside one process, if such a parent-chain exists and is retained. That still does not prove the end-to-end app semantics, because the visible problem is a fanout response from a wrong pi plus the legitimate target’s behavior. The files do not show that parent-chain data exists today or that the app can safely interpret both codes under multi-connection fanout.

**Recommendation:** Make typed errors a feasibility/design spike, not a confirmed scope item. Acceptance should require tests for both cases in the story: wrong-pi duplicate delivery does not render an error, and legitimate stale session still triggers re-sync (`story-foreign-session-user-message-tolerance.md:71`). If parent-chain/sibling state is unavailable, prefer an app-side handling rule scoped to `user_message` replies plus session-sync behavior rather than a premature wire change.

#### C2. Feature #3 is not just a soft dependency

**Position: challenge.** The epic says feature #3 is a “precondition for honest verification” but only a soft dependency for implementation verification (`epic-targeting-and-session-lifecycle-contracts.md:157`). That undersells it. For stale SDK context, the harness is the only evidence that a fix survives real `ExtensionRunner` invalidation. For replay identity, app and extension tests are still needed to prove live+replay idempotence. For reconnect, observability is needed before attribution.

**Recommendation:** Flip the ordering: feature #3 should be first-class critical path for implementation and for any contract section whose current truth depends on session replacement behavior. Allow only verified, noncontroversial doc cleanup before it.

#### C3. Reconnect bugs should feed the contract, not be “unblocked by” it

**Position: challenge.** The reconnect stories are observation gaps, not merely design gaps. Slow recovery needs timing attribution (`idea-mobile-drop-slow-recovery.md:47`), half-open TCP needs duplicate-auth cleanup confirmation (`idea-mobile-drop-half-open-tcp.md:37`, `:43`), dead-peer pumping needs relay/offline signal verification (`idea-extension-pumps-into-dead-app-peer.md:36`), swallowed outgoing message is not reproduced (`idea-mobile-outgoing-message-swallowed.md:19`), and not-delivered timeout is hypothetical (`idea-mobile-user-message-not-delivered-timeout.md:42`).

**Recommendation:** Move them under an observability/reproduction feature. The contract should be updated after the trace tells which state machine is wrong.

#### C4. `idea-mobile-conflates-transport-and-agent-state` is misfiled as “unblocked by reconnect contract”

**Position: challenge.** That item says the domain model already supports the fix: `AppTurnStatus` is already a proper turn-state enum, and the conflation happens at the projection/UI layer (`idea-mobile-conflates-transport-and-agent-state.md:49`, `:51`, `:54`). It recommends keeping transport and agent axes separate in UI projection (`:61`) and deriving turn phase from one source of truth (`:100`).

**Recommendation:** Route this under turn-state/UI projection work, not under a reconnect contract. If wire `room_meta` lacks `awaitingTool`, that is a turn-phase signal decision, not a reconnect state-machine decision.

### D. Interaction with the bold refactor DAG

#### D1. The relationship to the bold refactor work is silently inconsistent

**Position: challenge.** `docs/ARCHITECTURE.md` says the bold refactor DAG is “in-flight,” tracked in `.work/active/epics/epic-bold-*.md`, with 29 child features (`docs/ARCHITECTURE.md:271`, `:300`, `:301`). But there are no active `epic-bold-*.md` files under `.work/active/epics`; the matching epics are in release folders and marked `stage: done` (`.work/releases/v0.6.0/epic-bold-canonical-session.md:4`, `.work/releases/v0.6.0/epic-bold-transcript-event-log.md:4`, `.work/releases/v0.6.0/epic-bold-reachability-contract.md:4`, `.work/releases/v0.6.0/epic-bold-turn-state-machine.md:4`). This is itself foundation-doc drift.

**Recommendation:** Before starting this epic, reconcile `docs/ARCHITECTURE.md` with the actual substrate state: are the bold epics done, partially shipped, or still conceptually in flight? The answer changes this epic’s role.

#### D2. The overlap is concrete; this epic should consume or audit prior outputs, not duplicate them

**Position: reframe.** The released bold epics cover exactly the surfaces this epic wants to pin:

- canonical session: relay routes to `(to_pc, to_room)`, carries `session_id` opaquely, endpoints validate fail-closed (`epic-bold-canonical-session.md:39`, `:41`, `:64`, `:69`, `:72`);
- transcript event log: `TranscriptEvent` is canonical and hydration is replay, not replace (`epic-bold-transcript-event-log.md:17`, `:19`, `:50`);
- reachability: one `Reachability` state machine, `Connecting / Online / Degraded / Offline / Retrying`, with transition/backoff policy (`epic-bold-reachability-contract.md:17`, `:29`, `:44`);
- turn state machine: one algebraic `Turn` lifecycle replacing smeared booleans, including edge cases like compaction and session replacement (`epic-bold-turn-state-machine.md:17`, `:27`, `:33`, `:50`).

**Challenge:** The new epic does not articulate whether it is filling gaps left after these released epics, correcting stale docs from them, or designing parallel contracts. That creates a silent collision: feature #2’s reconnect contract overlaps released reachability; transcript identity overlaps released transcript-event-log; targeting/session identity overlaps released canonical-session; `awaitingTool`/UI projection overlaps released turn-state-machine.

**Recommendation:** Rename/reframe this epic as “contract gap audit and verification hardening after bold refactor,” or explicitly attach each child feature to the prior bold output it amends. Do not write new foundation sections as if the bold designs do not exist.

### E. Foundation-doc impact and rolling-foundation risk

#### E1. Current-state docs must not canonize unverified assumptions

**Position: challenge.** Documentation discipline says durable docs are current-state, not history, and should rewrite the owning artifact in place only when a position changes. The epic’s output is primarily `PROTOCOL.md` and `docs/ARCHITECTURE.md` current-state sections (`epic-targeting-and-session-lifecycle-contracts.md:162`). But several inputs are explicitly unconfirmed: the `#2` stale repro, reconnect attribution, peer-offline delivery, swallowed outgoing message, and no-echo timeout. Pinning those as “contract” before reproduction would convert hypotheses into durable truth.

**Recommendation:** Use a strict split:

1. **Verified current-state contract:** facts confirmed by code/tests/docs today, safe for `PROTOCOL.md` / `ARCHITECTURE.md`.
2. **Proposed target semantics:** keep in feature bodies until implemented/tested, or put in a clearly marked design section outside current-state docs only if the project has a durable design-proposal home.
3. **Open observations:** keep in work items and observability plans, not foundation docs.

The epic should require every foundation-doc claim to carry an evidence source: code path, passing test, live reproduction, or released work item.

## 4. The single most important question the operator must answer before starting design

**Is this epic allowed to pin target-state hypotheses in foundation docs, or must it pin only verified current-state contracts and route everything else through harness/reproduction first?**

## 5. Recommended reordering

1. **First: reconcile the bold-refactor/doc state.** Fix or explicitly account for `docs/ARCHITECTURE.md` claiming active `epic-bold-*` epics that are not in `.work/active/epics`, while matching released epics are `stage: done`.
2. **Promote feature #3 to hard critical path.** Build or honestly xfail the real-SDK session-replacement harness and add transport/cross-side observability before implementing session-replacement fixes or pinning replacement-dependent contract claims.
3. **Run reproduce/observe slices before reconnect contracts.** Attribute the reconnect cluster with phone-side and relay/extension traces; then update the reachability/reconnect contract from evidence.
4. **Narrow feature #1.** First document verified App↔Pi targeting facts missing from `PROTOCOL.md`; separately spike typed `session_mismatch` codes with feasibility tests for wrong-pi duplicate delivery vs legitimate stale re-sync.
5. **Split feature #2.** Separate (a) SDK stale-context lifecycle seam, (b) transcript-event identity/live-vs-replay idempotence, (c) reconnect/reachability. Tie each to the existing bold-refactor output it amends.
6. **Do not block already-fixed review stories on this epic.** `wrapActionCtx` and resume backfill should contribute invariants after review, not wait for the contract arc.
