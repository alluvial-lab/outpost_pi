---
id: backlog-fleet-update-from-mobile
created: 2026-09-07
updated: 2026-09-07
tags: [pi-extension, app, workflow, deps]
---

# Fleet pi update + rolling restart, drivable from mobile

Operator ask (2026-09-07): "run the pi updates and then execute restart
normally" — no fleet stop (revised same day: stopping is unnecessary).
Mobile control of the update cycle is "one of my last ties to the
workstation."

## Shape (revised — no stop phase)

Linux inode semantics make the stop unnecessary: `pi update` replaces
the binary while running pis keep their old inode; `pi update
--extensions` updates packages; every wrapper relaunch then picks up
the new binary automatically. So:

1. **Trigger from mobile — an "Update" button in the Outpost app**
   (operator direction 2026-09-07): a fleet-level action in the app's
   settings surface (not a chat command — this is device-ops, not
   conversation). The button sends the existing control-command plumbing
   to the primary paired pi; per-pi progress + final fleet status render
   in the same surface (phases: updating → arming → restarting →
   verified). Confirmation step required — it restarts every pi the
   phone can reach.
2. **Update phase**: that pi runs `pi update` + `pi update --extensions`
   (subprocess, captures result). No pis stop.
3. **Rolling restart via existing mechanisms**: the extension arms its
   own hot-reload restart (`.hot-reload-armed` + agent_settled →
   graceful exit → wrapper relaunches `pi` from PATH = new binary) AND
   broadcasts "arm-restart" to sibling pis over the **local agent mesh**
   (list_peers/agent_send — the broker already spans the fleet on this
   box; sibling outpost extensions subscribe and arm their own
   hot-reload). Each pi restarts at ITS next settle — turns finish,
   background work drains first (the v0.11.0 restart-gate deferral
   already covers this), making it a self-quiescing rolling restart.
4. **Report to phone**: per-pi arming status + final relay
   re-authentication confirmations as the fleet comes back.

## Pieces that exist (this is mostly assembly)

- Hot-reload arm + restart-gate deferral (background-aware) — shipped.
- Fleet uniformly under the restart wrapper — done 2026-09-07.
- Local mesh broadcast (agent_send) + sibling extension event handling.
- App control-command surface.
- herdr untouched (optional observer via the background-aware state).

## Open design points at scope time

- Mesh message shape + trust (mesh peers are trusted coding-agent
  endpoints per the trust model — confirm the arm-restart command
  deserves a explicit opt-in/ack per pi).
- pi update failure handling: report + skip restart (fleet stays on old
  binary — safe by construction).
- Cross-PC pis (mesh peers on other machines): include or explicitly
  local-only v1.

## Candidate lane

Feature, small-to-medium — mostly assembly of shipped mechanisms into
one command. Scope when the workstation tie should be cut.
