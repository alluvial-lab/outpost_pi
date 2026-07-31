---
id: story-hot-reload-agent-settled-hook-and-wrapper
kind: story
stage: drafting
tags: [pi-extension, workflow]
parent: feature-extension-hot-reload-via-process-restart
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-31
updated: 2026-07-31
---

# Hot-reload: agent_settled hook + room-scoped sentinel + exit-42 wrapper handshake

## Brief
Implements Units 1, 2, and 3 of `feature-extension-hot-reload-via-process-restart`.

Replaces the flawed `turn_end` + 500ms-timer + machine-global-sentinel + `RESTART_ON_EXIT_ZERO`
inline cut with:
1. An `agent_settled` hook (the true idle boundary — fires after ALL turns/retries/compactions settle, so no follow-up turn can be cut short).
2. A room-scoped sentinel (`.restart-pending-<roomId>`) so multi-pi (outpost + patchbay) don't contend.
3. An atomic `rename(2)`-based claim (no TOCTOU race).
4. Exit code 42 (`EXIT_DAEMON_FRESH_SESSION`, already handled by the supervisor) as the restart signal; `pi-restart-loop.sh` relaunches only on 42, stops on 0 (so `/quit` works) and on non-zero non-42 (crash safety).

## Acceptance criteria
- [ ] Restart fires at `agent_settled`, NOT `turn_end` — a queued follow-up turn is NOT cut short (regression test: seed turn + queued message → restart fires only after both settle).
- [ ] Sentinel is room-scoped: outpost pi (room A) and patchbay pi (room B) read different files; arming A does not restart B (contract test).
- [ ] Atomic claim: two processes racing the rename → exactly one wins (test).
- [ ] Toggle off + sentinel present → no restart (existing test preserved).
- [ ] `process.exit(42)` → wrapper relaunches; `process.exit(0)` → wrapper stops; non-zero non-42 → wrapper stops (wrapper behavior test).
- [ ] `_disposed` guard: if session replaces between `agent_settled` and exit, no exit (successor survives).

## Files
- `pi-extension/src/index.ts` — replace `_maybeRestartForExtensionReload` (turn_end) with `agent_settled` hook + room-scoped sentinel + atomic claim
- `pi-extension/src/extension.test.ts` — the regression + contract tests above
- `scripts/pi-restart-loop.sh` — exit-42 discrimination (delete `RESTART_ON_EXIT_ZERO`)
- `scripts/hot-reload.sh` — `arm` writes room-scoped sentinel (or delegate to an extension command); `off` globs `.restart-pending-*`

## Out of scope
- Lifecycle fence + M2/M4 hardening (M1 eliminated by removing the timer; M3 documented as session_sync backstop) → tracked in the sibling story `story-hot-reload-lifecycle-fence`.
