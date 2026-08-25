---
id: story-fix-app-post-quiescence-working-stuck
kind: story
stage: done
tags: [app, bug]
parent: null
depends_on: []
release_binding: v0.8.0
gate_origin: null
created: 2026-08-24
updated: 2026-08-24
---

# Live soak recovery probes now terminate before post-soak quiescence

## Symptom

The 300-second live soak with seed `2026082407` completed its scheduled faults
and kept replay, projection, ordering, and identity oracles clean, but timed out
for 30 seconds waiting for `working=false` during post-soak quiescence. The
shape followed the A→B→A multi-session exercise, a second `net_down` recovery
probe at 197 seconds, a long latency window, and a late airplane window.
Historical evidence is in
`.work/session-notes/live-soak-20260824T161455Z-2026082407/`; the current-tree
fails-before reproduction is
`.work/session-notes/live-soak-20260824T194451Z-2026082407/`.

## Root cause

This was a live-soak harness false positive, not an app room-snapshot edge lost
by `fcd2a8d0`. The second seeded `net_down` event sent an identity-window prompt
while no deferred fake-SDK turn was armed. `E2ePiHostRuntime` records an
unarmed user message but intentionally emits no `agent_start`/`agent_end`/
`agent_settled` lifecycle for it. The production extension therefore published
`working:true` when it accepted the re-sent prompt and never received the fake
SDK terminal event that would publish `working:false`.

Both failing captures prove this sequence: reconnect first delivered an
authoritative `rooms` snapshot with `working:false`, the recovery prompt then
produced `room_meta_updated` with `working:true`, and the later latency and
airplane reconnects correctly rehydrated authoritative `working:true`. The
app's 0.6.2 offline-stale projection and the edge-trigger fan-out both behaved
as designed; forcing the app idle would have contradicted Pi authority.

## Fix approach

For a standalone `net_down` identity recovery probe, the generated soak now
checks the fake Pi host's turn-control phase. If no turn is already armed or
pending, it arms a deferred reply before overlapping reconnect and send, waits
until the recovered prompt is pending, resolves it, and requires room working
to converge false before continuing. The seed's initial 15-second recovery
probe remains inside the deliberately pending staged turn and is not resolved
early.

## Regression test

`e2e/test_live_soak.py` adds
`test_generated_net_down_probe_has_a_terminal_turn_boundary`. It failed before
the repair because generated soak source had no conditional terminal boundary
for a standalone recovery probe. The deterministic live seed remains the
end-to-end regression because the defect requires the Android app, generated
soak, fake Pi SDK runtime, extension, relay, and toxiproxy fault sequence.

## Implementation notes

**Execution capability:** `sol/high`, selected for cross-boundary state-machine
diagnosis using two device captures, the 0.6.2 convergence diff, both fan-out
optimization diffs, generated Dart, and full live infrastructure.

**Files changed:**

- `e2e/live_soak.py` conditionally stages and resolves standalone identity
  recovery turns, then verifies their terminal working edge.
- `e2e/test_live_soak.py` asserts the generated recovery contract.
- Consumed `idea-soak-post-quiescence-working-stuck`.

### Four-step confirmation

1. The new generator regression fails before and passes after; all `21`
   `e2e.test_live_soak` tests pass.
2. `flutter analyze` passes and
   `flutter test --exclude-tags e2e --concurrency=2` passes (`940` tests).
3. `python3 e2e/live_soak.py --duration 300 --seed 2026082407` changes from the
   reproduced 30-second quiescence timeout to green, including final
   `working=false` and 11 clean oracle checkpoints. Evidence:
   `.work/session-notes/live-soak-20260824T195505Z-2026082407/report.md`.
4. The user's reported contract is restored without weakening authority: the
   recovery probe reaches a real fake-SDK terminal event, the Pi publishes
   idle, and the app converges from that authoritative update.

Final fresh-seed confirmation with both parked flakes consumed:
`python3 e2e/live_soak.py --duration 300 --seed 202608242021` passes with 13
clean checkpoints, zero outside-window churn clusters, and clean replay,
projection, ordering, and identity oracles. Evidence:
`.work/session-notes/live-soak-20260824T200357Z-202608242021/report.md`.

`e2e/expected-soak-findings.txt` remains empty. No adjacent issue was bundled.

## Bounded inline review

**Verdict: pass — no material blockers.** The final diff was reviewed against
the seed schedule's two `net_down` events. The phase guard preserves the first
probe's intentionally pending staged turn, while every later standalone probe
owns and closes exactly the turn it creates. The fix does not weaken the
post-soak oracle, synthesize app idle, or bypass the authoritative room
snapshot; it repairs the fake-SDK lifecycle that the oracle was measuring.
