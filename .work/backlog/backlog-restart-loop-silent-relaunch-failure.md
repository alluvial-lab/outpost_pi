---
id: backlog-restart-loop-silent-relaunch-failure
created: 2026-10-07
updated: 2026-10-07
tags: [pi-extension, bug, workflow]
---

# Restart-loop relaunches failed silently (Sep-26-era orphaned-PTS wrappers)

Fleet finding from the 2026-10-04 upgrade sweep (fleet CHANGELOG;
relayed by the projects session 2026-10-07):

During the outpost v0.13.0-era reboot, the ten Sep-26-era
orphaned-PTS `pi-restart-loop` wrappers all consumed their restart
markers, then their relaunches failed WITHOUT a trace — pi exited
immediately on the wrapper's `pi --continue` relaunch, the wrappers
stopped (crash safety held), and the output died with the PTYs.
Manual `pi --continue` in the same cwds works cleanly (verified in
orogen).

Root cause unknown. Candidates:
- environment the old wrappers carried (they predate the tmux-hosted
  generation — stale env as the wrapper's child context);
- startup-time contention (ten sessions resuming within ~30s);
- the wrapper's pts handling on relaunch.

State: all ten were recovered into durable tmux wrappers; the repro is
GONE (no orphaned-PTS wrappers remain) — diagnosis would need synthetic
reconstruction of the orphaned-PTS shape.

Sibling: `idea-restart-loop-fresh-start` (parked 2026-10-04) — common
thread: restart-loop relaunch paths that fail without a trace. Wrapper
mechanics live in `pi-extension/docs/daemon.md`; whichever item is
scoped first should fold the other's diagnosis lane in.
