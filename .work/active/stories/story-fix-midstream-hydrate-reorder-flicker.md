---
id: story-fix-midstream-hydrate-reorder-flicker
kind: story
stage: review
tags: [app, bug, ux]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-28
updated: 2026-08-28
---

# Mid-stream reconnect-hydrate causes transient message reorder + flicker in open chat

## Symptom (operator report, 2026-08-28)

On the current build (v0.10.1 release APK, 0.10.1+24), keeping the chat
open while turns stream shows intermittent message reordering and UI
flicker, worst around turn completion. Switching session rooms and back
clears it. Inconsistent.

## Evidence (capture-diagnosed)

Capture `debug/app-capture-2026-08-28T12-54-38-232Z-60682a1d74ff.bin`
(96 min, 8,468 rows, two-pane/landscape session):

- Protocol oracles ALL PASS (`ordering: ok`, `identity: ok`,
  `transcript_projection: ok`; no SWALLOW/blank-chat signatures) — durable
  order and final consistency are correct. The defect is a TRANSIENT
  UI-projection state.
- `connChannelLost: 11` (all `channelDone`) → `connHydrate: 13`.
  **9 of 13 hydrates land mid-turn** (workingConv ≥1 within ±3s), with
  `replayDedup: 60` merges and `wsIn` bursts up to 603 frames — phone
  doze/wake reconnect churn while the chat is open and streaming.
- Example: 11:45:15.03–.34 — two `working→false` transitions 100ms apart
  wrapped in connChannelLost → hydrate → 15 roomSnapshots + 60
  replayDedups. Turn-boundary + reconnect + full snapshot merge landing
  together is the worst-case window the operator sees.
- Prior-day capture (portrait session) shows the same clean oracles with
  22 hydrates — condition exists across layouts; two-pane just keeps the
  chat open through it.
- Separate, NOT the reorder cause: `layoutMode` churn (815 events,
  shell rebuild on every IME inset animation frame, bursts 34/s) —
  flicker contributor during typing only; turn completions do NOT
  correlate with layout bursts (0–1 events ±2.5s of working→false).

## Root cause

Condition level (proven): mid-turn reconnect-hydrate merges the
authoritative transcript snapshot into a live streaming chat; the merge
window paints intermediate projections (replayed committed events +
still-live streaming buffer) that transiently reorder/duplicate/flicker
before the next stable projection.

Mechanism level (pinned by the failing regression tests): this is a
compound candidate (c)/(a)/(b) race. The original `AgentDone` handoff in
`app/lib/data/sync/sync_service.dart:1313-1363` cleared the live cursor at the
old line 1319 before its terminal transcript batch was durable. The terminal
batch was then published at the old lines 1955-1961, before the disposable Hive
projection was materialized at the old lines 1962-1966. During a mid-turn
hydrate, the replay append is gated behind the same write chain, so the
`streamingStream` null emission could reach the UI while the committed
in-flight assistant row was still absent. After that early clear was removed,
the same race also exposed candidate (b): the queued `AgentDone` fallback could
append a second random assistant row after the hydrate had already accepted
the deterministic committed replay for the in-flight reply. `ChatViewModel`
consumes those independent emissions at
`app/lib/ui/chat/viewmodels/chat_viewmodel.dart:379-400` and assembles the
visible message list at `app/lib/ui/chat/viewmodels/chat_viewmodel.dart:515-523`,
so either intermediate could paint a false gap, reorder, or duplicate. The
reducer's internal batch application is atomic; the defect was the pre-durable
live handoff plus fallback construction ahead of the serialized hydrate, not
connection/reconnect logic. The fixed write-chain boundary is now
`app/lib/data/sync/sync_service.dart:1946-1997`: it materializes before
publishing and evaluates the terminal fallback against the post-hydrate
reducer.

## Fix approach

Pin the mechanism with a state-level failing test (simulate streaming +
mid-turn hydrate carrying the in-flight turn's committed events; assert
the emitted projection sequence never shows a reordered/duplicated
intermediate), then apply the minimal fix — most likely making the merge
publish one atomic projection (batched rebuild before notify) or gating
replayed in-flight-turn events while the streaming cursor is live, per
which candidate is confirmed.

## Regression test

To be added under `app/test/` (sync/viewmodel level) asserting: during
mid-stream hydrate with committed partial-turn events, every emitted
ChatState projection is order-stable (no transient swap/duplicate);
and the turn-completion handoff (streaming bubble → committed message)
emits without an intermediate state that removes the streaming content
before the committed message is present (flicker guard).

## Verification

`flutter analyze && flutter test --exclude-tags e2e` from `app/`.

## Implementation notes

- **Root cause:** the `AgentDone` path cleared the streaming cursor before its
  terminal transcript batch was durable, while the write path published the
  reducer before materializing the Hive projection. A hydrate racing that path
  could therefore paint a committed-prefix gap. Deferring terminal batch
  construction until the serialized write chain also prevents a legacy random
  fallback from duplicating a deterministic replay commit for the same reply.
- **Files changed:**
  - `app/lib/data/sync/sync_service.dart` — materialize accepted transcript
    projections before publish; defer terminal fallback decisions until prior
    hydrate writes settle; invalidate stale queued chunk projections; retain
    failure convergence.
  - `app/lib/domain/transcript/transcript_projection.dart` — expose the
    reducer's existing assistant-reply identity for the terminal dedupe guard.
  - `app/test/data/sync/sync_service_test.dart` — add deterministic mid-stream
    hydrate/completion projection-sequence and turn-completion handoff tests;
    update the terminal-append failure fixture for post-durable idle publication.
- **Fails-before evidence:** the new hydrate test observed a null streaming
  emission with no `in-flight-assistant` row; the handoff test observed a null
  emission with no `completed text` row. After only the publication reorder,
  the hydrate sequence additionally produced a third `still streaming` row,
  proving the replay/fallback duplicate and requiring the write-chain guard.
- **Four-step confirmation:**
  1. The new mid-stream hydrate and turn-completion tests pass, as do the full
     `test/data/sync/sync_service_test.dart` suite (118 tests) and the existing
     `test/ui/chat/chat_viewmodel_test.dart` suite.
  2. `flutter analyze` passes with no issues.
  3. `flutter test --exclude-tags e2e --concurrency=2` passes the full app suite
     (998 tests; the existing offline font-download diagnostics are non-failing
     test output).
  4. Reproduction trace: channel loss starts reconnect hydration; the 60-event
     replay remains behind the serialized write chain; a concurrent `AgentDone`
     invalidates stale chunk work but does not clear the live cursor. Hydration
     materializes the authoritative prefix plus in-flight committed message,
     then publishes the single stable null-stream projection; terminal handling
     observes that replay commit and does not append the random fallback. The
     subsequent `working → false` convergence is emitted from the same durable
     terminal projection. Session switching still resets the generation-bound
     turn state and room re-entry still rebuilds from the canonical session log.
- **Execution capability:** direct inline implementation; the sync writer,
  reducer contract, and deterministic regression tests formed one cohesive
  owner boundary. No connection/reconnect, pi-extension, or relay code changed.
- **Adjacent findings:** none discovered in this fix. The capture's
  shell-rebuild-per-IME-frame/layoutMode churn remains explicitly out of scope
  and is not bundled because it does not correlate with turn-completion
  reorder events.
