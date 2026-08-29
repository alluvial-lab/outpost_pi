---
id: backlog-new-wedge-bare-pi-room-teardown-without-exit
created: 2026-08-28
updated: 2026-08-28
tags: [pi-extension, bug, lifecycle]
---

# Mobile /new on a bare (unwrapped) pi tears down the room but never exits — half-dead wedge

**ABSORBED 2026-08-29** → `story-fix-new-wedge-bare-pi` (active). The
evidence below is the original incident record.

## Incident (2026-08-28, field + live diagnosis)

Operator issued mobile `/new` to their NextUp session (room `Vwjew_J1wVKU`,
served by the pi in `/home/agent/projects/nextup`, running bare — NOT under
`pi-restart-loop.sh`). Evidence chain:

- 22:39:33 — command DELIVERED (delivery.log `msg_delivered`, session tail
  `b574559a`; relay working-meta on Vwjew through 22:40:00).
- After 22:40:00 — Vwjew vanishes from the relay; the pi process stays
  ALIVE (uptime 3d, prompt-idle, footer still claiming relay state on
  other surfaces). The extension fenced + drained + detached the owner
  room, but the process exit (EXIT_FRESH_SESSION=42 path, daemon/rpc_child)
  never completed for this launch mode.
- Result: half-dead pi — live process, dead room. App shows the room
  peer-offline → action gating (`!isPeerOffline`) disables `/new` AND the
  restart action → operator permanently stuck (no in-app recovery path).
- Recovery was manual: `/quit` the pi via its herdr pane, relaunch under
  `pi-restart-loop.sh` (room re-authenticated on the relay within seconds).

Also observed: several herdr panes still run bare pis (any of them wedges
identically on mobile /new). `scripts/wrap-agents.sh` exists for turn-aware
live conversion — operator hygiene item.

## Defect shape

The `/new` shutdown path assumes the restart wrapper (or daemon child)
completes the process exit. When neither is present, the room teardown is
not paired with an exit or an in-process session replacement — the owner
channel is destroyed while the process lives on.

## Fix direction

- In the `/new` handler: when `OUTPOST_PI_UNDER_RESTART_WRAPPER` is unset
  and daemon mode is inactive, use the IN-PROCESS session replacement path
  (`bindReplacementContext` / mobile `session_new` re-arm — the mechanism
  already exists for the withSession recovery) instead of tearing down the
  room and relying on an exit that will not come.
- Alternatively/additionally: a liveness guard — if the room has been
  detached for a `/new` and the process has not exited within N seconds,
  complete the exit unconditionally (fail-closed to a restartable state)
  or re-bind the room.
- Test: /new against a pi harness with no wrapper env and no daemon →
  assert either in-process replacement completes (room re-bound,
  session_new published) or the process exits — never the detached-but-
  alive wedge.

## Candidate lane

Patch-lane fix story (bug in shipped v0.10.x surface; v0.11.0 is not a
regression — the wedged pi predated the batch). Bind at next patch cut.
