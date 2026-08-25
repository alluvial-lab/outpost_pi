---
id: story-fix-app-hydration-replay-should-materialize-not-stream
kind: story
stage: done
tags: [app, bug, ux]
parent: null
depends_on: []
release_binding: v0.8.0
gate_origin: null
created: 2026-08-24
updated: 2026-08-24
---

# Hydration replays completed turns through the streaming UI (typewriter backfill)

## Symptom
Operator report (2026-08-24, 0.7.3): opening a chat whose turn already
completed on the workstation TUI "plays" the turn on mobile
typewriter-style — every word replayed — instead of the finished turn
materializing whole. "Much faster than before" (the perf campaign sped
the replay machinery ~100×) but the correct behavior is invisible
backfill: replay applies, the settled transcript appears.

## Root cause
`sync_service.dart` replay admission (the session-history path,
~:2050-2100): each replay batch derives a projection and calls
`_emitStreaming(projection.streaming)` + `_setTurnView(...)` PER BATCH.
A completed turn's history contains its original delta events, so
hydration emits N growing streaming states to ChatViewModel → the UI
types the turn out. The FINAL projection already computes the settled
state (terminal events clear streaming); only the intermediate emissions
are wrong.

## Fix approach
Hydration-window emission coalescing: while applying session-history
replay (the history admission path — distinct from live envelope
handling), suppress per-batch streaming/turn emissions and emit exactly
once when the hydration pass settles (final projection: streaming +
turn view + steering + message rewrite). Live envelopes during an
ACTIVE turn are untouched (different path; ordering through _enqueue
keeps live-after-hydration correct). Multi-batch histories (sequential
ws frames) coalesce across the whole pass — window opens at history
admission start, closes at pass completion (all pending batches drained
or the pass goes idle).

## Regression test (fails-before)
Unit: feed a completed turn's delta-sequence history (N delta events +
terminal) through replay admission; assert streaming emissions == 1
terminal settle (or 0 intermediate growing states), not N. Widget:
ChatPage hydration with the same history renders the complete bubble
without passing through growing streaming states (spy on streaming
emissions). Edge: hydration of a turn still ACTIVE live (deltas arrive
live after hydration) — live streaming still emits (guard test).

## Verification notes
Perf note: this also deletes per-batch UI work during hydration (the
remaining per-frame cost of catch-up). Operator field-check remains for the
next shipped build: catch-up should populate rather than type.

## Implementation

**Execution capability:** `sol/high`, selected because this is a focused
single-service async ordering fix whose main risk is lifecycle/interleaving
correctness rather than broad design.

`SyncService` now opens a lifecycle-owned hydration emission window when the
first `SessionHistory` batch is admitted. Every replay batch still appends to
the canonical event log and materializes the same Hive projection through the
existing `_enqueue` write chain, but streaming/turn/steering publication is
deferred. The last pending admission publishes only the final projection. A
new live-turn observation epoch prevents a replay settle from overwriting a
live envelope that arrived while hydration persistence was draining; the
queued live deltas then publish per frame and retain authoritative room
`working:true`.

Files changed:

- `app/lib/data/sync/sync_service.dart`
- `app/test/data/sync/sync_service_test.dart`
- `app/test/ui/chat/chat_page_appbar_test.dart`

Regression evidence:

- Fails before: `multi-batch history hydration emits one settled projection`
  expected one terminal `null` streaming settle and observed
  `[null, null, null]` from the old per-batch publisher.
- The repaired test observes exactly one settle while preserving the complete
  projected prompt, assistant reply, compaction, and idle state.
- `live deltas queued immediately after hydration still stream per frame`
  observes `live one` then `live one live two`, and verifies both SyncService
  and ConnectionManager retain the active live turn after the hydration race.
- ChatPage widget coverage verifies a completed hydrated assistant reply is
  rendered as a whole bubble with no streaming chrome.

Confirmation:

1. Targeted hydration, live-ordering, and ChatPage widget regressions: pass.
2. `flutter analyze`: pass, no issues.
3. `flutter test --exclude-tags e2e --concurrency=2`: pass, 942 tests. The
   existing non-fatal Google Fonts fetch diagnostics appeared during the suite.
4. `e2e/run-live.sh state-shapes`: pass, 3 tests.
5. `python3 e2e/live_soak.py --duration 300 --seed 82608252`: pass; replay
   dedupe, transcript projection, ordering, identity, swallow, and blank-chat
   oracles all green. Scheduled-fault connection churn was reconciled.

**Bounded inline review verdict: PASS.** Review checked lifecycle replacement,
failed replay admission, duplicate replay rebuild, pending-window drain, and
live-after-hydration ordering. The first pass found that a stale hydration idle
settle could clear room `working` after an immediately queued live delta; the
live observation epoch and strengthened guard test fixed it. No material
findings remain. No adjacent issues were bundled or parked.
