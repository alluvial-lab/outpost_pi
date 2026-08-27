---
id: story-connect-attempt-deadline
kind: story
stage: implementing
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
