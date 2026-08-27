---
id: story-connect-attempt-deadline
kind: story
stage: done
tags: [app, bug]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-27
updated: 2026-08-27
---

# Connect attempts need a deadline — hung WebSocket connect wedges offline state

Field-diagnosed from capture 2026-08-27T23-26 (operator report #2 of the
"stays offline until force-close" class; this time with the wedge IN the
capture): 23:15:16 `connecting` → 10+ minutes of silence (app responsive —
layoutMode/route events during the window prove foreground) → force-close →
reopen 23:25:45 → online same-second. No retrying, no lifecycleFailure, no
timeout fired between.

## Root cause

The retry ladder (1→2→5→10→30s backoff, infinite) re-arms only on connect
FAILURE. A connect that never completes (TCP SYN blackholed — WiFi
associated-but-dead, NAT middlebox silent drop) parks the state machine in
`connecting` indefinitely. No failure event → no re-arm → permanent
"everything offline" while the process lives. Force-close is the only exit.

## Fix

1. Bound every connect attempt with a deadline (`.timeout()` ~15s, in line
   with the ladder's cadence) in connection_manager's connecting path.
2. Route deadline expiry into the EXISTING failure path — the retry ladder
   engages normally, the UI keeps its retrying states.
3. Consider (design-time): on app resume/foreground, if state has been
   `connecting` longer than the deadline, re-kick — belt for the doze-timer
   suspension case (the 617s/550s retrying→connecting gaps in the same
   capture suggest backgrounded timers also stall the ladder; separate
   concern, note only).

## Acceptance

- Regression test (break-it-first): a fake transport whose connect future
  never completes → assert the manager transitions to retrying within the
  deadline (fails against unfixed code).
- Existing reconnect tests stay green; full suite green (987 baseline).

## Implementation notes

- **Execution capability:** direct inline implementation. The defect was a
  focused app lifecycle/state-machine repair with one transport owner and a
  small resume integration seam; delegation would have added handoff risk
  without useful breadth.
- **Deadline:** every connection attempt is supervised for 15 seconds. This is
  long enough for ordinary relay/auth establishment while remaining inside the
  established 1→2→5→10→30-second recovery cadence.
- **Failure routing:** both timer expiry and the resume-time overdue signal
  raise `TimeoutException` through `_performConnect`; the attempt token is
  cancelled, late non-cooperative factory channels are closed, and the same
  retryable failure helper used by factory errors logs and schedules the normal
  retry ladder.
- **Resume belt:** `reconcileOnAppResume` asks `ConnectionManager` to expire a
  `StatusConnecting` attempt only when its injected wall clock shows an age at
  or above the deadline. This covers a suspended deadline timer without
  shortening a healthy 14-second attempt.
- **Files changed:** `app/lib/data/transport/connection_manager.dart`,
  `app/lib/main.dart`, `app/test/transport/connection_manager_test.dart`, and
  `app/test/main_lifecycle_test.dart`.
- **Regression evidence:** the virtual-time never-completing factory test failed
  before the fix with `StatusConnecting` where `StatusRetrying` was required;
  after the fix it reaches retry attempt 0 exactly at 15 seconds. The lifecycle
  test advances the injected wall clock without advancing fake timers, proves a
  14-second resume is a no-op, then proves a 16-second resume enters retrying.
- **Verification:** connection-manager reconnect suite 54/54; lifecycle suite
  4/4; `flutter analyze` clean; final full non-E2E suite 989/989 with
  `--concurrency=2` (987 baseline plus two regressions). One intermediate full
  run hit the existing loopback hedge test's five-second completion bound; its
  immediate isolated rerun passed, and the complete 989-test rerun then passed
  without changing that test or its behavior assertions.
- **Adjacent issues parked:** none.

## Bounded review

Standalone-story inline review found no material blocker. The 15-second bound
covers both the direct and hedged connect paths, preserves non-retryable relay
configuration handling, fences cancelled attempts from publishing late
channels, and leaves the public status/backoff sequence unchanged apart from
converging the formerly permanent `connecting` state.

## Closure

Completed 2026-08-27. The capture-proven SYN-blackhole wedge now converges into
`StatusRetrying`, and foreground resume independently re-arms recovery when
mobile timer suspension outlives the same deadline.
