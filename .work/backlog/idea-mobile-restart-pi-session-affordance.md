---
id: idea-mobile-restart-pi-session-affordance
created: 2026-07-03
updated: 2026-07-03
tags: [app, pi-extension, daemon, workflow]
---

# Mobile: no way to fully restart the Pi process (fresh session + relay) from the phone

## Observed

Operator (on phone) reports being "stuck not being able to full pi restart"
from mobile. The phone can drive a `/new`-equivalent (in-process session
switch), but has no affordance to **fully restart the Pi process** — which is
required to pick up a rebuilt `dist/index.js` (the AGENTS.md notes `/reload`
re-fires `session_start` against the already-loaded module and does NOT
re-`require` `dist/index.js`; only a full process restart picks up source
edits). So after an extension fix is built, a mobile-only operator cannot
make it live without workstation access.

Requested shape: "something like `/new` but restarts pi and connects to the
relay for my mobile to connect to."

## What exists today (grounded)

- **`session_new` action (app → extension):** `handleSessionNew`
  (`pi-extension/src/actions/handlers.ts:191-...`) calls
  `ctx.newSession({ withSession })` — an **in-process** session switch. It
  does NOT respawn the process, so a stale module in memory is not replaced.
  This is the right behavior for a "clear and start fresh conversation"
  intent, but it does not satisfy "restart pi to pick up code changes."
- **`EXIT_DAEMON_FRESH_SESSION` (exit 42):** the daemon/RPC path already
  has a contract for this — a child exits 42 and the supervisor respawns it
  with `forceFreshSessionOnNextSpawn = true` (drops `--continue`, creates a
  brand-new session file instead of resuming)
  (`src/daemon/rpc_child.ts:55,225,264-265,412`, `src/daemon/supervisor.ts:602`).
  This is the mechanism that would satisfy the request — but it is only
  triggered internally today, not exposed as a mobile action.
- **`/remote-pi daemon restart`** (`src/extension/command_surface/daemon_commands.ts:207`):
  a TUI/slash-command path to restart a daemon via supervisor RPC. Not
  reachable from the phone.
- **`restartSupervisor`** (`src/extension/command_surface/supervisor_restart.ts`):
  restarts the supervisor itself (heavier — restarts the whole fleet). Not
  what's wanted for a single-session fresh restart.

## Proposed shape (not committed — for design time)

Add a mobile-facing action (e.g. `session_restart` or extend `session_new`
with a `mode: "fresh_process"` flag) that, when the pi is running as a
daemon under the supervisor:

1. Ensures the relay is up (or will reconnect on respawn) so the phone can
   reattach.
2. Triggers `EXIT_DAEMON_FRESH_SESSION` (exit 42) so the supervisor respawns
   a fresh pi process — picking up a rebuilt `dist/index.js` and starting a
   clean session.
3. Returns an ACK to the phone so it knows to expect a transient disconnect
   + reconnect (the new process gets a new module instance, re-binds relay,
   re-publishes room_meta; the app's existing reconnect + `session_sync`
   hydration handles the rest).

For a non-daemon (interactive TUI) pi, a process restart from the phone is
not really possible — the TUI owns the process. In that mode the action
should either be hidden or degrade to `session_new` with a clear "restart
not available in interactive mode" message.

## Design questions to settle

- **Daemon vs interactive detection:** how does the extension know it's
  running under a supervisor? (RPC mode flag? supervisor RPC socket
  presence?) The action should be conditionally available.
- **Relay continuity:** does the respawned process re-bind to the same relay
  room/identity so the phone reconnects to the *same* room, or does it get a
  new room? The app's reconnect path assumes room continuity via
  `peers.json` + room metadata — confirm the respawn preserves the room id.
- **ACK vs fire-and-forget:** the phone needs to know the restart was
  accepted (so it can show a "restarting…" state) before the socket drops.
  An `action_ok` before the exit-42, then a `bye`/disconnect, then
  reconnect.
- **Scope creep risk:** this is adjacent to the broader
  `epic-remote-session-resilience-refactor` mobile-control surface. Keep it
  as a narrow affordance, not a fleet-management UI.
- **Naming:** `session_restart`? `pi_restart`? Distinguish clearly from
  `session_new` (which is in-process conversation-clear, not
  process-restart).

## Relationship to other work

- Required for mobile-only deployment of **any** pi-extension fix that needs
  a `dist/` reload — including the resume-backfill fix just shipped in
  `story-mobile-chat-blank-on-pair-after-pre-pair-work` (operator cannot
  make it live from the phone without this).
- Distinct from `idea-mobile-session-control` (broader session control UX)
  — this is specifically the "restart the process" affordance.

## References

- `pi-extension/src/actions/handlers.ts:191-...` — `handleSessionNew` (in-process).
- `pi-extension/src/daemon/rpc_child.ts:55,225,264-265,412` — `EXIT_DAEMON_FRESH_SESSION` + `forceFreshSessionOnNextSpawn`.
- `pi-extension/src/daemon/supervisor.ts:602` — supervisor respawns on exit 42.
- `pi-extension/src/extension/command_surface/daemon_commands.ts:207` — `restart` (TUI-only today).
- `pi-extension/src/extension/command_surface/supervisor_restart.ts` — full supervisor restart.
- `app/lib/data/actions/actions_repository.dart:283` — `SessionNew` action (app side).
- `app/lib/ui/chat/quick_actions/` — quick actions sheet (where a restart action would surface).
- `AGENTS.md` — "Reload vs restart" section (`/reload` does not re-`require` `dist/`).
- `.work/active/stories/story-mobile-chat-blank-on-pair-after-pre-pair-work.md` — fix that motivates this affordance.
