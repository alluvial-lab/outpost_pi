---
id: bug-pair-delivery-nextup-nxuc
created: 2026-10-09
updated: 2026-10-09
tags: [pi-extension, mcp, relay, bug, claude-lane]
---

# Pair-only delivery failure: nextup resident ↔ nxuC (Claude lane) — both directions time out

Defect report from fleet-root (projects#2, msg id 01a121db-2c2d-763a-be8c-dec32bd7153f,
2026-10-09). Repro data below verbatim-ish; live operational impact — both nextup
lanes had routing decisions blocked on it.

**Symptom.** Peer-to-peer delivery between exactly two registrations fails
BIDIRECTIONALLY (agent_send → send-timeout / no ACK), while each delivers to
and receives from a third peer (fleet-root) normally:

- `/home/agent/projects/nextup@nextup` — pi resident, main checkout, herdr
  pane `wJ:p1`, fresh 1.0.4 process, idle + relay-green at test time.
- `/home/agent/projects/nextup/.claude/worktrees/mesh@nxuC` — Claude lane,
  registered via the `OUTPOST_PI_MCP_CWD` worktree workaround.

- nextup → nxuC: 6+ timeouts across two threads starting ~17:12Z Oct 9
  (before and after the lane's recovery from the dead-mesh-child wedge —
  the wedge was real but separate, fixed by a fleet-root lane reboot; the
  pair failure persisted after it).
- nxuC → nextup: two timeouts ~a minute apart (~12:07–12:08 local), resident
  verifiably idle/done with green relay.
- Control: fleet-root ↔ each of them: Delivered, multiple times, including
  immediately around the failing window.

**Suspect surface (per fleet-root):** v0.13.0 cross-room routing between a
main-checkout room and a CWD-workaround worktree registration — same family
as the name-scoped `acquireCwdLock` work. Alternative candidate: stale
per-peer sibling/membership cache on the nextup side pointing at a dead
nxuC registration (the wedge-era child), while fleet-root's cache is fresh.

**Control datapoint (outpost):** outpost ↔ nxuC full round trip WORKED at
2026-10-07T04:59Z under the then-live mesh child (pre-wedge), so the
defect is pair-specific, not nxuc-global.

**Repro:** agent_send nextup-resident → nxuC and reverse while both idle,
fleet-root (or outpost) as control. Timing details from fleet-root or the
nextup transcripts.
