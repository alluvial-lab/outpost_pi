---
id: story-hot-reload-lifecycle-fence
kind: story
stage: done
tags: [pi-extension, workflow]
parent: feature-extension-hot-reload-via-process-restart
depends_on: [story-hot-reload-agent-settled-hook-and-wrapper]
release_binding: v0.4.0
gate_origin: null
created: 2026-07-31
updated: 2026-08-11
---

# Hot-reload: lifecycle fence + M2/M4 hardening

## Brief
Hardens the PID-scoped `agent_settled` restart path from
`story-hot-reload-agent-settled-hook-and-wrapper`.

- **M1 lifecycle fence**: the synchronous hook checks `_disposed` before the
  idle recheck, after claiming, and immediately before writing the marker and
  signalling. A replacement can leave the armed request for its successor,
  while a stale claim is removed.
- **M2 stale state**: `hot-reload.sh off` removes every process-scoped armed,
  identity, claim, marker, and legacy pending file. Startup sweeps identity
  files whose PIDs are no longer alive.
- **M3 delivery honesty**: `agent_settled` is not an end-to-end WebSocket flush
  acknowledgment. Pi's graceful shutdown provides a bounded local drain; the
  app rehydrates from `session_sync` after reconnect, and ingress during the
  quiescing window receives recoverable `delivery_pending`.
- **M4/M5 local boundary**: the state directory must be an owner-only 0700
  directory and state files must be owner-only regular 0600 files. `lstat`
  rejects symlink/non-regular armed requests before any read or unlink.

## Acceptance criteria
- [x] `_disposed` guard: session replacement during the settled hook → no exit (test).
- [x] `hot-reload.sh off` removes all process-scoped pending state and legacy pending globs.
- [x] Symlink armed request files are rejected (the hook `lstat`s and refuses non-regular files).
- [x] `OUTPOST_PI_HOME` dir with permissive perms (>0o700) → hook refuses to read state (logs a warning).
- [x] Startup sweeps runtime identities for dead PIDs.
- [x] M1/M3 bounded-drain and reconnect/session_sync guarantees are documented at the hook and ingress boundary.

## Files
- `pi-extension/src/index.ts` — lifecycle fence, secure state admission, dead-identity sweep
- `pi-extension/src/extension.test.ts` — lifecycle, filesystem, cleanup, and sweep acceptance tests
- `scripts/hot-reload.sh` — secure directory/file validation and complete `off` cleanup

## Implementation notes
- Added owner/permission checks for the state directory and regular files, with
  safe `lstat` admission so symlinks cannot redirect request reads or cleanup.
- Added `_disposed` checks around the synchronous claim/marker boundary and reset
  the hot-reload gate plus stale claim when a successor session starts.
- Added startup cleanup for dead `.runtime-self-<PID>` files and expanded shell
  `off` cleanup to all process-scoped state plus legacy `.restart-pending-*` files.
- Verification: `./node_modules/.bin/tsc --noEmit`, full Vitest (962 passed, 3 skipped),
  `./node_modules/.bin/tsc`, and `bash -n` for both hot-reload scripts passed.
