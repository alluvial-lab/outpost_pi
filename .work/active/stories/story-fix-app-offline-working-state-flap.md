---
id: story-fix-app-offline-working-state-flap
kind: story
stage: implementing
tags: [app, bug]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-23
updated: 2026-08-23
---

# Room working-state flaps idle every ~10s while disconnected instead of holding a reconnecting state

## Symptom
Same capture: during offline windows (20:34:29-20:35:29, 20:36:16-20:37:37)
`workingConv` fires `mark_room_working False reason=inactive_or_not_live`
every ~10s — 16 flips in one gap. Operator-perceived as "state flakes": a
turn in flight visibly flickers working/idle repeatedly.

## Root cause (to confirm)
The offline liveness check (ConnectionManager ~10s cadence /
inactive_or_not_live emitter) re-asserts idle on every tick while
disconnected, fighting the room's last authoritative working state. Same
substrate as the late-echo backstop (story-fix-app-session-rotation-late-
echo-sticks-working, 2311bd7d): working corrections need convergence, not
repetition.

## Fix approach
While the connection is down (or hydrating), the room state converges to a
distinct disconnected/reconnecting projection: no repeated idle flips —
the liveness emitter must not re-fire the same correction on every tick
(edge-triggered, not level-triggered), and a mid-turn room should read
"reconnecting", not "idle". Preserve the offline-idle convergence for rooms
that were genuinely idle before the drop.

## Regression test
Unit: working room -> disconnect -> 3 liveness ticks -> assert exactly ONE
workingConv transition (to the disconnected state), not three; on reconnect
+ snapshot the state resolves to the authoritative value. Fails-before.

## Verification notes
Capture signature to re-check post-fix: count of `inactive_or_not_live`
workingConv rows per offline window == 1.
