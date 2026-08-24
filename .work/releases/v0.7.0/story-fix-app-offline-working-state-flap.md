---
id: story-fix-app-offline-working-state-flap
kind: story
stage: done
tags: [app, bug]
parent: null
depends_on: []
release_binding: v0.7.0
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

## Root cause
`SyncService._setTurnView` deliberately replays terminal/idle corrections when
it sees the same idle projection again, and `ConnectionManager.markRoomWorking`
treated every one of those calls while offline as a fresh
`inactive_or_not_live` idle transition. It logged every level-triggered call,
cleared cached `working`, and advanced the working-authority epoch even though
no live room snapshot existed. The transport projection was already capable of
representing this interval as stale/reconnecting; the correction path was
incorrectly collapsing it into authoritative idle.

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

## Implementation notes
- **Execution capability:** Sol/high, selected because the change touches the
  reconnect state machine and the session/turn epoch fence.
- **Files changed:** `app/lib/data/transport/connection_manager.dart`,
  `app/test/data/transport/connection_manager_test.dart`.
- **Regression test:** `disconnect projects stale once without repeated idle
  corrections` drives working -> channel loss -> three idle correction ticks ->
  reconnect snapshot. Fails-before evidence: cached working became false before
  hydration (the first assertion failed), and the old path would emit three
  `inactive_or_not_live` rows. It now proves one disconnect-edge diagnostic,
  a stale/reconnecting projection during the gap, preserved cached truth, and
  authoritative idle after the reconnect snapshot.
- **Confirmation:** targeted regression passed; the three connection-manager
  suites passed (74 tests); `flutter analyze` reported no issues; full
  `flutter test --exclude-tags e2e --concurrency=2` passed (912 tests). Device
  signature confirmation is deferred to the orchestrator soak.
- **Bounded inline review:** PASS. Offline corrections now return before epoch
  mutation, so 2311bd7d's late-echo fence remains owned by fresh authoritative
  idle snapshots. Explicit disconnect/dispose still clear state, room-end and
  snapshot paths still converge idle, and reconnecting UI derives from the
  existing status + stale projection rather than a second state enum.
- **Adjacent issues parked:** none.
