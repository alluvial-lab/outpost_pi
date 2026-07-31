---
id: story-hot-reload-lifecycle-fence
kind: story
stage: drafting
tags: [pi-extension, workflow]
parent: feature-extension-hot-reload-via-process-restart
depends_on: [story-hot-reload-agent-settled-hook-and-wrapper]
release_binding: null
gate_origin: null
created: 2026-07-31
updated: 2026-07-31
---

# Hot-reload: lifecycle fence + M2/M4 hardening

## Brief
Implements Unit 4 of `feature-extension-hot-reload-via-process-restart`. Depends on the
core hook+wrapper story landing first (it provides the `agent_settled` hook this hardens).

- **M1 (timer not fenced)**: eliminated by the `agent_settled` redesign (no timer). This story adds the `_disposed` guard between `agent_settled` and `process.exit(42)` — if the session replaces mid-hook, don't exit; the successor picks up the next request.
- **M2 (stale sentinel)**: `hot-reload.sh off` globs and removes all `.restart-pending-*` files (not just one). The toggle-off check at hook time already ignores sentinels without the toggle.
- **M3 (dropped messages)**: document that the app rehydrates via `session_sync` on reconnect; the restart window is ~2s. No quiescing state in v1 (out of scope — session_sync is the correctness backstop).
- **M4 (OUTPOST_PI_HOME perms)**: validate the dir is `0o700` owner-only at hook time; reject symlink/non-regular sentinel files.

## Acceptance criteria
- [ ] `_disposed` guard: session replacement between `agent_settled` and `process.exit(42)` → no exit (test).
- [ ] `hot-reload.sh off` removes ALL pending sentinels (`rm -f .restart-pending-*`), not just one.
- [ ] Symlink sentinel files are rejected (the hook `lstat`s and refuses non-regular files).
- [ ] `OUTPOST_PI_HOME` dir with permissive perms (>0o700) → hook refuses to read sentinels (logs a warning).

## Files
- `pi-extension/src/index.ts` — `_disposed` guard in the `agent_settled` hook; `lstat` + perm validation on the sentinel path
- `scripts/hot-reload.sh` — `off` globs `.restart-pending-*`; `arm` validates the dir perms
