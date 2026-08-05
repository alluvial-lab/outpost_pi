---
id: story-new-session-restart-fresh-extension-exit
kind: story
stage: done
tags: [pi-extension, bug]
parent: feature-mobile-slash-command-invocation
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-04
updated: 2026-08-04
---

# /new from mobile: extension exits for a fresh session (interactive)

Core of `feature-mobile-slash-command-invocation`. The mobile `/new` fails
because `newSession()` is gated behind `ExtensionCommandContext` (only present
during a slash command), which the interactive extension doesn't have
pre-command. Fix: mirror the **daemon's restart-fresh path** for the interactive
case — ack, reset session state, exit with the fresh-session code so the process
manager restarts **without `--continue`** (→ fresh session).

## Change

- `pi-extension/src/index.ts` `case "session_new"`: when no command-capable
  context exists, acknowledge + reset + exit with `EXIT_FRESH_SESSION` only if
  the daemon supervisor or interactive restart wrapper owns the process.
- Unmanaged interactive processes return a structured `action_error`; they
  never exit. Keep the wire `session_new` contract unchanged.

## Acceptance

- [x] Mobile `/new` with no command-context → ack + reset + exit(fresh-session)
      when a daemon supervisor or interactive restart wrapper owns the process;
      the manager restarts without `--continue` → fresh session.
- [x] The `newSession unavailable (no command ctx yet)` throw is retired; the
      in-process handler now accepts only a command-capable context.
- [x] Daemon path (`OUTPOST_PI_DAEMON=1`) unchanged — no regression.
- [x] Focused extension tests and typecheck pass. The full suite passed all 965
      tests (3 skipped) but returned nonzero only for the pre-existing tracked
      hot-reload restart-sweep `ENOENT` unhandled-error flake.

## Implementation notes

- Renamed the shared process-manager handshake to `EXIT_FRESH_SESSION` and kept
  its established value `42`; daemon `RpcChild`/`Supervisor` and the interactive
  wrapper now key on the same code.
- A missing `newSession` command capability exits only when either
  `OUTPOST_PI_DAEMON=1` or `OUTPOST_PI_UNDER_RESTART_WRAPPER=1`. The wrapper
  branch sends `action_ok`, resets the Outpost-Pi session projection, and then
  schedules exit 42 after the existing 100 ms acknowledgment window.
- Without either owner env, the extension sends `action_error` with
  `fresh_session_restart_unavailable: /new is not available in this agent mode`;
  it does not reset, exit, or route through the retired raw throw.
- The 11 herdr-managed agents are intentionally not migrated here. Until an
  operational follow-up launches them under the restart wrapper, mobile `/new`
  on those agents fails safely with the structured unavailable error rather
  than killing the agent pane.

## Ordering

`depends_on: []`. Unblocked the wrapper restart-mechanism story, which keys on
the shared fresh-session exit code.
