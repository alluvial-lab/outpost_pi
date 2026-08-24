---
id: story-fix-app-replay-silently-dropped-on-session-rotation
kind: story
stage: done
tags: [app, bug]
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: null
created: 2026-08-24
updated: 2026-08-24
---

# Replay batch silently dropped when the session rotated during a disconnect window

## Symptom
v0.7.0 UAT battery: `e2e/run-live.sh state-shapes` intermittently failed at
`exerciseLongUptimeShape` because the marker-sliced capture contained no
`replayDedup` rows immediately after reconnect. Transcript stability and
uniqueness still passed.

Evidence: `/tmp/bat-shapes2.log` (original runner failure) and
`/tmp/replay-root-probe-{2,3,4}.log` (root-cause probes).

## Root cause
The proposed production diagnosis was disproved before implementation. Temporary
logging around every replay-admission guard showed that the reconnect histories
carried the same session id as the active transcript, mapped seven events, and
reached the `ReplayDedupEvent` logging loop. Neither the session/key mismatch
nor stale-history guard fired. The failure was an E2E observation race: the
transcript-stability predicate was already true from persisted rows, so the
harness could export the ring before the asynchronous replay writer's diagnostic
rows became observable. The preceding fixed-offset ring slice was separately
rotation-unsafe; the pending marker patch correctly replaced it.

The unrelated `action_ok reason=session_mismatch` line came from the earlier
multi-session scenario, not the failing long-uptime replay.

## Fix approach
Keep the rotation-proof marker and the exact non-empty replay assertion. Poll the
exported capture until a `replayDedup` row exists after that marker, then run the
same marker-survival, non-empty replay, transcript-uniqueness, and idle-state
assertions. No production replay-admission semantics were changed because the
observed replay was admitted correctly.

## Regression test
`app/integration_test/support/live_device_harness.dart` remains the regression
boundary. It failed before the fix in repeated device runs and now waits only
for the asynchronous evidence it already required; it does not weaken or remove
the marker-sliced `replayDedup` assertion.

## Implementation

- **Execution capability:** sol/high, selected because the initial diagnosis
  conflicted with intermittent device evidence and required instrumented live
  replay tracing before any code change.
- **Files changed:**
  - `app/integration_test/support/live_device_harness.dart`
- **Root-cause confirmation:** one pre-fix run passed and two pre-fix runs failed;
  the fully instrumented failing run reached replay mapping and diagnostic
  logging with matching active/history session ids. No admission guard fired.
  All temporary logging was removed.
- **Fails-before evidence:** `/tmp/replay-root-probe-2.log` and
  `/tmp/replay-root-probe-4.log` both failed with an empty marker-sliced replay;
  probe 4 recorded matching session tails plus `mapped=7` and `logging=7`.
- **Confirmation:**
  - `flutter analyze` — PASS, no issues.
  - `flutter test --exclude-tags e2e --concurrency=2` — PASS, 927 tests.
  - `e2e/run-live.sh state-shapes` — PASS, 3 tests.
  - `e2e/run-live.sh mesh` — PASS, 2 tests; all three mesh scenario markers passed.
  - `e2e/run-live.sh capture-delivery` — PASS, 1 test.
- **Bounded inline review:** PASS. The change preserves the marker-survival and
  non-empty replay assertions, waits at the asynchronous evidence boundary,
  changes no production state semantics, and leaves no probe logging behind.
- **Adjacent issues parked:** none. The disproved replay-rebind proposal was not
  implemented as speculative production behavior.
