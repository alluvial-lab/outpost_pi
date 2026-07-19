---
id: idea-mobile-restart-pi-session-affordance
kind: story
stage: done
tags: [app, pi-extension, daemon, workflow]
parent: feature-mobile-native-session-process-control
depends_on: [idea-mobile-session-control]
release_binding: null
gate_origin: null
created: 2026-07-03
updated: 2026-07-18
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

## Design

This story is the implementation unit **Full-process restart affordance** and
follows `idea-mobile-session-control` because both controls share the existing
Quick Actions sheet and action repository. Add a danger-styled `Restart Pi
process` row beside `New session`, with a standalone confirmation explaining
that the current conversation is cleared and the phone will briefly reconnect.
Cancel sends nothing; confirmation delegates to the existing
`IActionsRepository.newSession()` method, so the wire remains the canonical
`session_new` action rather than gaining a `session_restart` discriminator.

On the existing daemon path, the extension must continue to send `action_ok`
before resetting its session projection and scheduling `process.exit(42)`;
the supervisor then respawns the fresh process. The app clears its local
transcript only after that ACK and lets the normal reconnect/session-sync
hydration establish the successor state. A non-daemon interactive Pi can only
do the existing in-process new-session behavior, so copy must qualify the
process promise as applying to a supervised Pi rather than silently claiming
universal process restart. `/reload` is intentionally not added because it
does not re-import `dist/index.js`.

Implementation does not add process-management code, a new wire type, or a
second relay path. Focused extension tests should guard the existing daemon
ordering and room/identity continuity; app widget/repository tests should
cover confirmation, no-reset-before-ACK, expected reconnect feedback, and
failure preservation. Cross-surface reconnect assertions are tracked in
`feature-mobile-native-session-process-control-reconnect-verification`.

## Implementation

- Added a danger-styled `Restart Pi process` tile to Quick Actions with its own
  confirmation and `Cancel` / `Restart Pi` controls.
- Restart delegates to the existing `QuickActionsViewModel.newSession()` /
  `IActionsRepository.newSession()` path, so it sends only canonical
  `session_new`; no `session_restart` wire action or `/reload` affordance was
  introduced.
- The confirmation qualifies process respawn as supervised-Pi behavior and
  explains transcript loss plus the expected brief disconnect. After the ACK,
  the app clears the local mirror and shows `Restarting Pi — reconnecting…`;
  failures leave the transcript intact.
- Danger styling, cancel, rejection, and controlled ACK/reconnect-feedback
  widget paths are covered by Quick Actions tests.

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
