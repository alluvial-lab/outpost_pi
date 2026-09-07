---
id: feature-fleet-update-from-mobile
kind: feature
stage: drafting
tags: [pi-extension, app, workflow, deps]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-09-07
updated: 2026-09-07
---

# Fleet pi update + rolling restart, drivable from mobile

## Brief

The operator's ask (2026-09-07): "run the pi updates and then execute restart
normally" — drivable from the phone, because fleet update control is "one of
my last ties to the workstation." An "Update" button in the Outpost app sends
the existing control-command plumbing to the primary paired pi, which runs
`pi update` + `pi update --extensions` and then arms a self-quiescing rolling
restart across the local fleet via hot-reload arm + local agent-mesh
broadcast. No fleet stop phase: Linux inode semantics make stopping
unnecessary — running pis keep their old binary's inode, and every wrapper
relaunch picks up the new binary automatically.

This is mostly assembly of shipped mechanisms (hot-reload arm, restart-gate
deferral, mesh broadcast, app control-command surface) into one fleet-level
device-ops action. UI surface is app settings: a confirmation-gated Update
button plus per-pi phased status (updating → arming → restarting → verified) —
existing app patterns, align at feature-design.

## Strategic decisions

- **v1 mesh scope: local fleet only** (operator, 2026-09-07) — arm-restart
  broadcast targets local broker peers on this VM only; cross-PC mesh peers
  are explicitly out of scope for v1 (single VM surface in use). A cross-PC
  extension is a clean follow-up feature if the fleet ever spans machines.
- **Not a chat command** (operator direction, 2026-09-07) — the trigger is a
  fleet-level action in the app's settings surface; this is device-ops, not
  conversation.
- **No stop phase** (revised 2026-09-07 from the original ask) — inode
  semantics + wrapper relaunch make stopping the fleet unnecessary.

## Simplification opportunity

No new restart or confirmation mechanism — deliberately reuses the hot-reload
arm + `.hot-reload-armed` + agent_settled gate, the v0.11.0 restart-gate
deferral (turns finish, background work drains first), and the existing app
control-command ack surfaces. herdr stays untouched (optional observer via
the background-aware state). If any per-pi restart path duplicates wrapper
logic, prefer driving the existing wrapper rather than a second restart
implementation.

## Design input (shaped at park, 2026-09-07)

### Shape

1. **Trigger from mobile — an "Update" button in the Outpost app**: a
   fleet-level action in the app's settings surface. The button sends the
   existing control-command plumbing to the primary paired pi; per-pi progress
   + final fleet status render in the same surface (phases: updating → arming
   → restarting → verified). Confirmation step required — it restarts every pi
   the phone can reach.
2. **Update phase**: that pi runs `pi update` + `pi update --extensions`
   (subprocess, captures result). No pis stop.
3. **Rolling restart via existing mechanisms**: the extension arms its own
   hot-reload restart (`.hot-reload-armed` + agent_settled → graceful exit →
   wrapper relaunches `pi` from PATH = new binary) AND broadcasts
   "arm-restart" to sibling pis over the **local agent mesh**
   (list_peers/agent_send — the broker already spans the fleet on this box;
   sibling outpost extensions subscribe and arm their own hot-reload). Each
   pi restarts at ITS next settle — turns finish, background work drains
   first (the v0.11.0 restart-gate deferral already covers this), making it a
   self-quiescing rolling restart.
4. **Report to phone**: per-pi arming status + final relay re-authentication
   confirmations as the fleet comes back.

### Pieces that exist (this is mostly assembly)

- Hot-reload arm + restart-gate deferral (background-aware) — shipped.
- Fleet uniformly under the restart wrapper — done 2026-09-07.
- Local mesh broadcast (agent_send) + sibling extension event handling
  (`command_surface/local_mesh_commands.ts`).
- App control-command surface.
- herdr untouched (optional observer via the background-aware state).

### Open design points for feature-design

- Mesh message shape + trust (mesh peers are trusted coding-agent endpoints
  per the trust model — confirm the arm-restart command deserves an explicit
  opt-in/ack per pi).
- pi update failure handling: report + skip restart (fleet stays on old
  binary — safe by construction).
