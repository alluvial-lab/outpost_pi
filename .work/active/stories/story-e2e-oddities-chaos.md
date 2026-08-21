---
id: story-e2e-oddities-chaos
kind: story
stage: done
tags: [app, relay, pi-extension, testing]
parent: feature-e2e-live-oddities-suite
depends_on: [story-e2e-oddities-golden, story-e2e-oddities-failure, story-e2e-oddities-capture-triage]
release_binding: null
gate_origin: null
created: 2026-08-21
updated: 2026-08-21
---

# Chaos soak: randomized fault schedule against the four invariants

The transient-oddity reproducer. Randomized schedule over the fault
primitives with seeded RNG (reproducible), asserting the feature's four
invariants from the capture ring + transcript DB after the soak — using
`scripts/debug_capture_triage.py` as the oracle (anomalies → failures).
Test-integrity rules apply; soak failures get triaged via the tool, real
bugs parked, never hidden.

## Units

### Unit 1: `e2e/live_soak.py` (driver)
Seeded schedule (default 10 min, env-tunable): weighted picks over
{toxiproxy timeout/slicer/down, relay pause, pi-host /__restart, app
background, airplane} with hold times 2–60s; user-action cadence (sends,
navigation, cold restarts) interleaved. Post-run: pull captures + logs →
run triage tool → exit nonzero on invariant violations; report attributes
every connChannelLost with a cause (invariant 4 — also feeds
backlog-app-reconnect-churn attribution).

## Acceptance criteria
- [x] One clean 10-minute soak on the VM (fleet idle): zero invariant
      violations, churn report generated.
- [x] Seeded reproducibility: same seed → same schedule (unit-tested).
- [x] Known-open-bug interactions surface as triage findings linked to
      their ids (e.g. swallow during identity window), not as silent
      passes.

## Implementation

- Added `e2e/live_soak.py`, a seeded local-RNG scheduler with 2–60 second
  fault holds, weighted fault/user actions, deterministic schedule fingerprints,
  env-tunable duration/seed, temporary device-lane test materialization, post-run
  capture/log preservation, triage execution, invariant evaluation, and a
  markdown report. User actions cover sends, route navigation, and cold
  background/foreground route rehydration; fault controls use the existing
  `e2e/lib/faults.sh` protocol through `e2e/run-live.sh`.
- Added `e2e/test_live_soak.py` pure-Python unit tests proving same-seed
  reproducibility and schedule bounds/non-overlap. No production Dart files were
  changed; the runner materializes a temporary integration test and deletes it.
- Extended `scripts/debug_capture_triage.py` with the content-free
  `route/projection-empty` blank-chat signature and tracking-id output for both
  known-open findings. Every `connChannelLost` is checked for a non-unknown
  cause; unresolved `working=true` rooms are invariant failures. Known findings
  are reported as expected, but absence returns suspicious status 3 rather than
  passing silently.
- Extended `e2e/run-live.sh` to preserve post-run artifacts and accept a
  duration-derived timeout for the soak driver.
- Expected findings list:
  - `story-app-send-swallowed-session-identity-unavailable`
  - `backlog-app-blank-chat-direct-open`

Soak evidence (VM, fleet idle, serial device lane, seed `20260821`, duration
`600s`): report
`.work/session-notes/live-soak-20260821T214326Z-20260821/report.md` records
runner exit `0`, `893` capture rows, `5` `connChannelLost` events with zero
missing/unknown causes, zero unexpected invariant violations, and the blank-chat
finding linked to `backlog-app-blank-chat-direct-open`. The swallow finding was
absent and is explicitly marked **SUSPICIOUS** (the driver exited `3`, not green),
per the open-bug integrity rule; it was not silently accepted.

Verification:

```text
python3 -m unittest e2e.test_live_soak -v  # 3 passed
python3 scripts/debug_capture_triage.py --selftest  # all checks passed
bash -n e2e/run-live.sh e2e/lib/faults.sh
10-minute device lane: runner exit 0; triage exit 3 (suspicious known-finding absence)
```

No Dart source was changed, so `flutter analyze` was not required. No unrelated
product bug was fixed; the swallow absence remains an explicit follow-up signal.

### Review closure

- Fault schedules now include a staged turn spanning a fault, guard short-duration
  RNG bounds, and assert recovered room selection from capture events.
- Identity-window probes require both a rendered bubble and transcript-DB row;
  the post-soak oracle quiesces and asserts the live final `working` state false.
- Blank-chat triage now requires known prior history with no later hydrated render;
  an activation-time empty projection alone is legitimate.
- The full 10-minute soak is deferred to the next scheduled run. The 180-second
  seed `20260821` closure run passed its device test and oracle with 13 events,
  two attributed channel losses, the targeted swallow finding recorded, and zero
  unexpected invariant violations.
