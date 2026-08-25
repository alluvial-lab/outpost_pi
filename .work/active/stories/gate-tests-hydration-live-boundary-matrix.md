---
id: gate-tests-hydration-live-boundary-matrix
kind: story
stage: done
tags: [testing, app, bug]
parent: null
depends_on: []
release_binding: v0.8.0
gate_origin: tests
created: 2026-08-25
updated: 2026-08-25
---

# Exercise hydration coalescing at every live-turn boundary

## Priority
High

## Value evidence
Item: `story-fix-app-hydration-replay-should-materialize-not-stream`. The
contract distinguishes a replay window's one settled publication from live
turn frames that race that window. Current coverage blocks the first replay
append and queues two live chunks before releasing it
(`app/test/data/sync/sync_service_test.dart:875-939`). It does not pin the
boundary immediately before final hydration publication, live terminal/error
frames during hydration, a new history admission at drain, or lifecycle
replacement/failure while a window owns pending admissions. `_finishHistoryHydration`
publishes based on counters plus `_liveTurnObservationEpoch`
(`app/lib/data/sync/sync_service.dart:2249-2267`), so those interleavings are the
stable state-machine risk behind the reported typewriter regression.

## Gap type
bug-regression / explicit async interleaving / state transition

## Suggested test
```dart
// Add explicit started/release barriers around final append, materialization,
// and hydration finish. Cover a decision table:
// - live chunk before final settle: no stale null/idle publication;
// - live chunk after settle: one settled hydration publication, then live;
// - live done/error during hydration: terminal state wins exactly once;
// - another history batch admitted at drain: still one final publication;
// - session rotation, append failure, and dispose: no stale publication.
// Assert public streaming/turn/steering emissions and materialized rows.
```

## Test location (suggested)
`app/test/data/sync/sync_service_test.dart`

## Implementation

Extended the existing append-gated hydration coverage into the terminal and
lifecycle matrix. The focused set now pins:

- multiple history admissions drain to one settled projection;
- live chunks admitted before the final replay append suppress a stale settle
  and retain per-frame streaming;
- live `agent_done` and `error` frames during hydration each publish one
  working→idle transition, suppress queued streaming work, and cannot be
  reopened by the late hydration finish;
- append failure and disposal while the hydration window owns an admission
  produce no stale streaming publication or materialized row.

All races use explicit append-started/release completers; there are no elapsed
sleep assumptions. Session replacement is already pinned by the adjacent
stale-append and held-read rotation barriers, while the three-admission test
pins a new batch joining the same window before drain. No product defect was
found.

Verification:

- `flutter test test/data/sync/sync_service_test.dart --concurrency=2` was run
  over the full file: the new assertions initially exposed test expectation
  mistakes only; after correction, the focused hydration matrix passes 5/5.
- `flutter test test/data/sync/sync_service_test.dart --name hydration --concurrency=2` (5 passed).
