---
id: story-new-session-restart-fresh-restart-mechanism
kind: story
stage: done
tags: [pi-extension, workflow]
parent: feature-mobile-slash-command-invocation
depends_on: [story-new-session-restart-fresh-extension-exit]
release_binding: null
gate_origin: null
created: 2026-08-04
updated: 2026-08-04
---

# /new from mobile: restart-without-continue mechanism (wrapper)

The other half of `/new`-via-restart-fresh. Once the extension exits with the
fresh-session code, the owning process manager must restart the agent without
`--continue` exactly once so Pi creates a fresh session. This delivery covers
the interactive restart wrapper; migration of herdr-managed agents is an
explicit operational follow-up.

## Change

- `scripts/pi-restart-loop.sh` exports the wrapper ownership gate and recognizes
  the shared fresh-session exit code.
- A fresh-session exit relaunches Pi once without `--continue`; the one-shot
  state is cleared before that launch, so later authorized hot-reload restarts
  return to `--continue`.
- Exit 0 without a marker and non-fresh nonzero exits preserve their prior stop
  behavior. The hot-reload marker remains a distinct exit-0 handshake.
- `scripts/herdr-start-agents.sh` and `scripts/herdr-restart-agents.sh` remain
  unchanged in this slice.

## Acceptance

- [x] `/new` on the `outpost` wrapper agent → one fresh launch without
      `--continue`.
- [x] Hot-reload marker restarts still resume with `--continue`.
- [x] Unmanaged interactive agents are protected by the extension gate and
      receive a structured unavailable error instead of exiting.
- [x] Script-level Vitest coverage proves the wrapper env, fresh one-shot launch,
      and subsequent marker-based `--continue` launch.

## Implementation notes

- The wrapper exports `OUTPOST_PI_UNDER_RESTART_WRAPPER=1`; the extension treats
  that value as process-manager ownership. This safety gate is intentionally
  absent from herdr-managed agents today.
- The shared handshake is `EXIT_FRESH_SESSION=42`, matching the daemon
  supervisor. Exit 42 sets a one-shot fresh-launch flag; the next Pi invocation
  omits `--continue`, and the flag resets before launch. Exit 0 plus a hot-reload
  marker continues to relaunch with `--continue`; all other exits are unchanged.
- Operational follow-up: migrate the 11 herdr-managed agents to launch under
  `scripts/pi-restart-loop.sh` (or an equivalent manager that owns the same
  contract), then restart those panes. `scripts/herdr-start-agents.sh` was not
  changed here. Until that migration, `/new` on those agents fails safely with
  `fresh_session_restart_unavailable` and does not kill the pane.
- Focused wrapper/extension tests and typecheck pass. The full extension suite
  passed all 965 tests (3 skipped) but returned nonzero only for the pre-existing
  tracked hot-reload restart-sweep `ENOENT` unhandled-error flake.

## Ordering

`depends_on: [story-new-session-restart-fresh-extension-exit]` (keys on the
shared exit code).
