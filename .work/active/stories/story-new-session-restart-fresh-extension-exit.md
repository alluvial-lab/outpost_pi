---
id: story-new-session-restart-fresh-extension-exit
kind: story
stage: drafting
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

- `pi-extension/src/index.ts` `case "session_new"` (~:2979): today the
  `OUTPOST_PI_DAEMON` branch (`:2981`) handles no-command-ctx via ack + reset +
  `process.exit(EXIT_DAEMON_FRESH_SESSION)`. **Extend that to the interactive
  case** — when `freshCommandActionCtx()` is null (no command context), do the
  same ack + `_resetSessionForNew(msg.id)` + exit with the fresh-session code,
  regardless of daemon mode. (Decide whether to reuse
  `EXIT_DAEMON_FRESH_SESSION` or a new `EXIT_FRESH_SESSION` code that the wrapper/
  herdr mechanism keys on.)
- Keep the wire `session_new` contract + ack (`action_ok`); the change is the
  exit-for-fresh behavior, not the wire.

## Acceptance

- [ ] Mobile `/new` with no command-context → ack + reset + exit(fresh-session);
      the process manager restarts without `--continue` → fresh session (new
      `session_start reason=new`).
- [ ] The `newSession unavailable (no command ctx yet)` throw is gone for the
      interactive case.
- [ ] Daemon path (`OUTPOST_PI_DAEMON=1`) unchanged — no regression.
- [ ] `corepack pnpm test` green; typecheck clean.

## Ordering

`depends_on: []`. Unblocks the restart-mechanism story (the wrapper/herdr side
must restart-without-`--continue` on this exit code).
