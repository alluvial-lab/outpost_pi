---
id: story-fix-app-concurrent-replay-admission-race
kind: story
stage: done
tags: [app, bug]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-23
updated: 2026-08-23
---

# Concurrent hydration paths admit duplicate replay events (reordering/duplication on mobile)

## Symptom

Operator report (2026-08-23, new Pixel, APK 0.5.1): "message reordering
issues" on mobile. Captures `debug/ef1-…c9cc1cea9d20.bin` and
`debug/ef5-…c9cc1cea9d20.bin` (9h rings, 03:57→13:22Z) show
`replay_dedup: VIOLATION` — 68 of 340 accepted event ids admitted 2–3×
each. `scripts/debug_capture_triage.py` flags it; `transcript_projection`
and `ordering` oracles pass, so the admission layer double-writes below the
projection oracle's radar.

## Root cause

The capture did **not** contain duplicate accepted event ids. `ReplayDedupEvent`
logged only the final 12 characters of each deterministic event id. Those ids
end in the SDK millisecond timestamp, so distinct user, assistant, and tool
facts emitted at one SDK timestamp all appeared as the same identifier (the
reported `787455597602`/`787457546765` values are timestamps). The triage oracle
then grouped those lossy suffixes as duplicate admissions. Production
`SyncService._enqueue` already serializes the persisted-store read, append, and
projection rewrite; an explicit two-replay interleaving confirms one accepted
row and one drop.

## Fix approach

Retain the existing serialized persisted-store admission owner and replace the
lossy event-id suffix in diagnostics with a bounded SHA-256 correlator over the
full event id. Keep the legacy `eventIdTail` JSON key so capture readers remain
compatible; only its collision semantics change. Verify concurrent replay
admission explicitly rather than restructuring a write pipeline that already
has the required ownership.

## Regression test

Unit: two interleaved hydration passes sharing the replay store; same event
id in both passes must admit exactly one row. Fails-before evidence
required. Live: the soak's replay-dedup oracle already detects this shape —
a soak slice green after the fix.

## Verification notes

- Evidence: `debug/ef5-11f1-93fc-c9cc1cea9d20.bin` rows 03:57:43.304-.306,
  04:03:17.646-.651; triage output `replay_dedup: VIOLATION`.
- Related: `story-fix-app-blanked-projection-during-churn` (the inverse
  failure of the same admission substrate — fix ordering may matter).

## Implementation notes

- **Execution capability:** `sol/high`; capture interpretation and an async
  persistence interleaving both required careful root-cause discrimination.
- **Files changed:** `app/lib/data/sync/sync_service.dart`,
  `app/lib/domain/contracts/debug_log.dart`,
  `app/test/data/sync/sync_service_test.dart`, and the diagnostic test drift in
  `app/test/data/debug/debug_capture_routing_test.dart`.
- **Failing regression:** `replay diagnostics distinguish different events with
  one server timestamp` failed before with one correlator
  (`Set:['787455597602']`, expected length 2). It passes after hashing the full
  event id.
- **Admission verification:** `interleaved history replays admit one durable
  event` blocks the first append, starts a second replay, then releases both;
  the shared store contains one row and diagnostics report `[false, true]`.
- **Four-step confirmation:** both focused tests pass; the full
  `sync_service_test.dart` file passes (99 tests); `flutter analyze` passes;
  full `flutter test --exclude-tags e2e --concurrency=2` passes (890 tests).
  The capture's same-millisecond suffix collisions can no longer produce the
  reported replay-dedup violation in a new ring, while actual repeated full ids
  still share a digest and remain detectable.
- **Adjacent issues parked:** none; repeated `route` entry events are benign
  no-op activations, not additional writers, and the capture's ordering and
  transcript-projection oracles both passed.

## Bounded inline review

**Verdict: pass.** The change corrects the evidence boundary without weakening
replay admission or the oracle. The correlator remains content-free and bounded,
and the explicit interleaving test proves the production single-owner behavior
that the original hypothesis assumed was missing.
