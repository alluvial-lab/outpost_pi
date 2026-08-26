---
id: story-mobile-transcript-reorder-after-backlog-flush
kind: story
stage: done
tags: [app, bug]
parent: null
depends_on: []
release_binding: v0.9.0
gate_origin: null
created: 2026-07-27
updated: 2026-08-26
---

# Transcript reordered on phone after backlog flush + reconnects

## Observation (operator, 2026-07-27, live on the fixed 0.3.0+2 build)

Phone transcript displayed out of order. Expected order:
"what else is on the .work board?" (user) → board report (assistant) →
"let's groom" (user) → groom start (assistant). Actual display:
"let's groom" → the LATER assistant reply ("While the semantic pass runs…")
→ then the earlier "what else is on the .work board?" + board report — i.e.
a later assistant message sorted ABOVE the earlier user+assistant pair.

## Context (likely contributors)

Same day the channel carried: a ~450-frame offline backlog flush
(send_seq 66→514), multiple reconnects (5G/WiFi transitions), a pairing
with generation replacement, and the pairing-race fix build. Prime
suspects: backlog flush insertion position, replay/replay-dedup ordering,
timestamp skew vs arrival order in transcript projection.

## Direction

Reproduce with the captures in debug/ (938/94f series) + relay log
(2026-07-26/27): determine whether the jumbled rows are flushed-backlog
events inserted by arrival rather than canonical order, or a
projection/sort defect in the app's transcript ordering
(msgs_v3 + replay path). Check `sessionHistoryEventToTranscriptEvent`
identity/ordering and the live-append vs replay-merge path.

## Root cause (forensic, confirmed 2026-08-03)

**Defect:** the per-session Hive log is read in **arrival (`seq`) order**,
not canonical (`ts`) order, and the projection trusts that input order.
Authoritative history that was generated during an offline gap but never
delivered live arrives only on the reconnect `session_history` replay; it is
appended with a fresh high `seq` despite an older server `ts`, so it renders
*after* newer live events that bookend the gap. That is exactly the observed
symptom (a later assistant reply above an earlier user+assistant pair).

Evidence chain (all in `app/`):

1. `data/local/transcript_event_store_hive.dart` `_readBox` sorts by
   `(seq, eventId)` — `seq` is a monotonic **insertion/arrival** counter
   assigned at append time (`_maxSeq(box.values) + 1`). Dedup is correct
   (idempotent by `eventId`: `if (box.containsKey(event.eventId)) continue;`),
   but ordering is by arrival, not by the canonical server `ts` that every
   record also persists (`TranscriptEventRecord.ts`).
2. `domain/transcript/transcript_projection.dart` `deriveTranscriptProjection`
   builds its `ordered` list by **iterating the input as given** (deduped by
   `eventId`) — it performs **no `ts` sort**. So the store's arrival order
   flows straight into the rendered `authoritativeMessages` list.
3. The **authoritative rendered events** — `UserMessageConfirmed`,
   `AssistantMessageCommitted`, `ToolRequested`/`ToolFinished`,
   `CompactionRecorded` — all carry a **server/SDK `ts`** on both paths (live
   `message_end`-driven commits use the SDK `ts`; replay uses `event.ts` via
   `DateTime.fromMillisecondsSinceEpoch`). So among authoritative bubbles a
   `ts` order is canonical. **Caveat (load-bearing for the fix):**
   `AssistantDeltaReceived` (deltas) carry **phone-receipt**
   `DateTime.now()` (`sync_service.dart:894`) and `UserMessageSubmitted`
   carries **local clock** (`:381`). The projection's lifecycle reducer
   (`streaming`/`turn`/`steering`/tool-merge) is **order-sensitive** and was
   designed around **arrival order across these mixed clocks** — so a
   whole-log `ts` sort is NOT a valid global order (a phone-receipt-time delta
   can sort after a terminal compaction/done event and resurrect `streaming`).

Forensic confirmation from the captures (`debug/*.bin` are NDJSON written by
`DebugLogImpl`, gated by `Preferences.debugLogging`):

- Capture `963-…` (2026-07-26 17:41 → 2026-07-27 02:30, the observation
  window): 1,440 `replayDedup` decisions — **1,193 dropped (deduped) and 247
  KEPT (appended as new)**, in dense bursts at 02:20–02:27 on 07-27. Those 247
  backfilled authoritative events are the reorder trigger: appended at high
  `seq`, older `ts`.
- Capture `9c5-…` (07-27 14:13–14:17): 300 `replayDedup`, **all 300 dropped**
  (0 appended) — by the afternoon the store was stable, so any visible reorder
  originated in the 963 window and was inherited.

Not the cause: dedup (works correctly by `eventId`) or identity collision
(`serverReplayEventId` is deterministic and shared by live + replay).

## First fix attempt (REJECTED by cross-model review)

Sort the store read (`_readBox`) by `(ts, seq, eventId)`. **Wrong:** it broke
3 convergence tests in `sync_service_test.dart` (compaction-live, compaction-
replay, history-replay — all `Expected: false / Actual: true` on `streaming`).
Cause: deltas (phone-receipt `ts`) sorted after terminal server events and
resurrected `streaming`. Reverted. Lesson: the store read must stay
arrival/`seq`-ordered because the lifecycle reducer depends on it across mixed
clocks.

## Fix attempt 2 (projection render-sort — REVERTED, see Review 2)

**Status (2026-08-03):** implemented and verified green for the primary bug
AND for review-1's convergence finding (521 tests pass across domain/data/
chat-UI), but review 2 found it still mixes clocks for tool bubbles. Reverted
to a green tree; the design below is preserved for whichever follow-up path is
chosen. No code is committed.

Decouple the two contracts: **arrival order for lifecycle reduction; canonical
server `ts` for the rendered authoritative bubbles.** The store read is
unchanged. In `deriveTranscriptProjection`, the arrival-order pass that derives
`turn`/`streaming`/`steering`/tool-merge stays byte-for-byte the same; only the
**output `authoritativeMessages` list is sorted by canonical `ts`** (stable,
arrival-order tiebreak) before `messages = [...authoritativeMessages,
...localTail]` is assembled.

Why this is safe where the store-level sort was not:

- `AssistantDeltaReceived` never enters `authoritativeMessages` (it only sets
  `streaming`), so phone-receipt `ts` never participates in the render sort.
- Every authoritative bubble carries server/SDK `ts` (point 3), so the render
  sort is single-clock and canonical.
- Optimistic `UserMessageSubmitted` lives in `localTail` (after the sorted
  authoritative list) and carries local `ts`; it is excluded from the render
  sort, so its clock never pollutes authoritative ordering.
- The lifecycle pass is untouched, so the 3 convergence tests (and all
  `turn`/`streaming` semantics) are preserved.

Implementation: thread each authoritative message's event `ts` (ms) + an
arrival index into parallel maps during the pass (`appendAuthoritative` /
`upsertTool`), then sort `authoritativeMessages` by `(ts, arrivalIndex)`. The
existing prompt-before-reply fixup stays as a same-`ts` safety net.

## Regression test (projection layer)

Feed `deriveTranscriptProjection` events in arrival order where a backfill
pair has an **older server `ts`** than an already-seen live pair (the
backlog-flush scenario): live user(T)+assistant(T+100), then replay-backfill
user(T+50)+assistant(T+60). Assert `projection.messages` ids are
`['cli_1','cli_2','msg_2','msg_1']` (canonical), not arrival
(`['cli_1','msg_1','cli_2','msg_2']`). Red before the fix, green after. The
convergence suite must stay green (no lifecycle-state regressions).

## Review 1 — store-level sort (REQUEST CHANGES)

Cross-model review (`openai-codex/gpt-5.6-sol`, xhigh) of attempt 1: REQUEST
CHANGES. Material: a whole-log `ts` sort mixes clocks (`AssistantDeltaReceived`
is phone-receipt `DateTime.now()`, `sync_service.dart:894`) and broke 3
`streaming`-convergence tests in `sync_service_test.dart`. Latent (pre-existing,
not introduced): optimistic-submission `turn`/`steering` skew; destructive
`upsertTool` on result-before-request backfill. Confirmed-safe: no read path
bypasses `_readBox`; home tiles read `sessions_index_v3`; migration displays
through the store; per-session isolation holds. → Attempt 1 reverted.

## Review 2 — projection render-sort (REQUEST CHANGES)

Re-review of attempt 2: REQUEST CHANGES, but **review-1's convergence defect is
resolved** (lifecycle pass unchanged; sort runs only on the rendered bubble
list after all lifecycle state is derived). New material finding: **tool
bubbles still mix clocks.** Live `ToolRequested`/`ToolFinished` carry no server
`ts` on the wire (the extension omits `ts` from `tool_request`/`tool_result`,
`pi-extension/src/index.ts:1356-1388`), so the app stamps them with phone
`DateTime.now()` (`sync_service.dart:1148-1169`); replay later supplies the
canonical Pi `ts` (`session_history_replay.dart`) but `upsertTool` keeps the
first-observed (phone) `ts`. Under phone/Pi clock skew a tool can misorder
relative to Pi-timestamped narrations — a regression, since arrival order
previously kept tools correctly positioned. Same root issue as review 1,
narrower: **the app lacks consistent canonical server-ts provenance across all
authoritative event kinds on the live path** (deltas, tools; also flagged:
`UserInput` without `ts` and legacy/error assistant commits,
`sync_service.dart:1016-1067,1296-1299`). Reviewer requires a tool regression
(skewed live receipt + canonical replay correction) before commit. → Attempt 2
reverted; 521-test green restored.

## Open question / follow-up paths (operator decision)

The primary bug is fully diagnosed and the user/assistant/compaction fix is
verified, but a fully-correct canonical-ordering fix needs server-ts provenance
for tools (and a delta/lifecycle answer). Candidate paths:

- **(A) Wire change (proper):** extension broadcasts `ts` on `tool_request`/
  `tool_result` (it already records Pi `Date.now()` for history); app uses it;
  `ToolRequested` owns the tool bubble's sort ts. Paired wire change
  (extension ↔ app), schema update. Biggest scope; fully correct.
- **(B) App-only anchor:** at projection time, give each tool bubble the `ts`
of its preceding server-ts message (the narration it follows) instead of its
own phone-receipt `ts`; tools then inherit a server clock on both live and
replay paths without a wire change. Needs its own design pass + review for
edge cases (first-message tool, multi-tool runs, compaction reset).
- **(C) Park as a feature:** the work grew from inline-fix to design-bearing
(ts-provenance audit across event kinds + canonical ordering). Re-scope as a
feature under `.work/active/features/` with the two candidate fixes above as
child stories; keep this story's forensic as the foundation.

Other noted (pre-existing, parked): transient partial projections during a
backlog rewrite (`box.put` per row + `SessionReadRepository` emits per row);
`upsertTool` ignores `authoritativeIds.add` success (broader `ValueKey`
invariant).

## Status

**Re-scoped (2026-08-03):** operator chose **C → A** — park as a feature and
implement via the wire change. The fix work lives in
`feature-canonical-transcript-ordering` (direction A); this story is its
forensic foundation and stays open until the feature's render-sort child lands.

Tree reverted to green (no code committed). Forensic + both fix attempts + the
scope decision are preserved here; the feature carries the implementation
plan, wire-pairing/deploy note, and child-story sketch.

## Standalone follow-on execution boundary (2026-08-26)

The parent feature's direction-A wire change shipped in `v0.4.0` and its
projection child already landed the canonical render sort. This item is now
tracked as a standalone corrective follow-on rather than a child checkpoint.
The app-side contract under test here is direction B at the reconnect boundary:
keep lifecycle reduction in arrival order, but materialize authoritative
bubbles by canonical server timestamp with a stable arrival tiebreak across
incremental replay batches. Duplicate reconnect replay must be idempotent, and
the result must equal a clean fold of the complete durable event log.

## Provenance
Promoted to standalone (parent: null) on 2026-07-28 when the parent epic
`epic-targeting-and-session-lifecycle-contracts` was retired. The epic's
observability thesis had self-executed (cross-side observability shipped,
3 of 5 cluster bugs resolved, 2 unreproduced with no recurrence in 3+ weeks),
so the epic arc was closed. This story is the fresh 2026-07-27 live
observation with a concrete repro direction, retained as the standalone
follow-on recorded below.

## Implementation notes

- Execution capability: inline land mode; the production reducer/render-sort fix
  is already present in the released parent implementation, so this bounded
  follow-on adds the missing incremental reconnect regression evidence rather
  than duplicating the shipped fix.
- Review weight: standard, from the caller/autopilot note; bounded inline review
  applies because this is now standalone (`parent: null`).
- Files changed: `app/test/domain/transcript/transcript_projection_test.dart`
  and this story body/frontmatter.
- Tests added: `reconnect backfill preserves canonical order across incremental
  hydration` applies live events, an older-timestamp replay batch, and a
  duplicate replay to one reducer, then compares it with a clean durable-log
  fold. It asserts the changed suffix begins at the insertion point and that
  duplicate reconnect history is a no-op.
- Simplification: none; the existing canonical reducer remains the single
  projection implementation and no store-level timestamp sort was reintroduced.
- Discrepancies from design: the checked-in forensic body still records the
  earlier C→A feature decision, while the caller requested this post-release
  direction-B standalone boundary. The parent feature's code and child
  projection fix are already released in `v0.4.0`; this item therefore lands
  as corrective regression coverage and does not change the wire or store.
- Adjacent issues parked: none.
- Verification: `flutter analyze` passed; focused transcript projection tests
  passed (27); the three streaming/turn convergence sentinels in
  `sync_service_test.dart` passed serially; the two sync-service behavior tests
  that failed in the concurrent full run also passed when isolated serially.
  The required full `flutter test --exclude-tags e2e --concurrency=2` run was
  attempted but collided with active app workers (two sync tests failed only
  under the concurrent run, and pairing teardown/sink cleanup failed). A
  serial full-suite classification reproduced unrelated pairing-viewmodel
  timeouts plus offline `google_fonts` fetch errors; no transcript behavior
  failure was waived or altered.
- Collision notes: concurrent workers are modifying `app/` during this run.
  No lifecycle internals or their files were edited; only the isolated
  transcript test and this item were staged.

## Bounded inline review

- Verdict: approved; no material blockers found.
- The regression drives the same reducer through live append, older canonical
  replay insertion, duplicate replay, and clean-fold comparison. It preserves
  arrival-order lifecycle reduction and proves canonical render ordering across
  the reconnect boundary without touching the rejected store-level sort.
