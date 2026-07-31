---
id: story-hot-reload-agent-settled-hook-and-wrapper
kind: story
stage: implementing
tags: [pi-extension, workflow]
parent: feature-extension-hot-reload-via-process-restart
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-31
updated: 2026-07-31
---

# Hot-reload v2: PID-scoped arming + agent_settled quiescing gate + graceful SIGTERM + marker handshake

## Brief
Implements the revised design (all 4 units) of `feature-extension-hot-reload-via-process-restart`.

The prior design (turn_end + rename-sentinel + exit-42 + process.exit) was reviewed and found
to have 5 blockers. The revised design addresses all of them:

1. **PID-scoped identity + arming** (B5): extension writes `.runtime-self-<PID>` on session_start
   (PID + nonce + epoch). Operator arms via `/outpost-pi hot-reload arm`; agent arms via
   `scripts/hot-reload.sh arm` (discovers PID from bash parent, reads nonce). Armed request is
   `.hot-reload-armed-<PID>` with the nonce — multi-pi can't cross-fire, PID reuse is detected.

2. **agent_settled handler with quiescing gate + ctx.isIdle() recheck** (B2): handler runs
   synchronously (no await → no preemption), sets `_hotReloading` gate, rechecks `ctx.isIdle()`.
   If a run started → defer. The gate rejects new messages with `recoverable: true` in
   `_deliverUserMessage` so the app resends on reconnect.

3. **Exclusive claim via O_CREAT|O_EXCL** (B1): `.claimed-<PID>` file with `flag: "wx"`. Exactly
   one agent_settled wins.

4. **Graceful SIGTERM + durable restart marker** (B3): `process.kill(pid, "SIGTERM")` (NOT
   process.exit). Pi's SIGTERM handler fires session_shutdown → working=false → relay.stop →
   exit 0. The wrapper checks for `.restart-marker` after exit 0: present → relaunch, absent → stop.

5. **Daemon exclusion** (B4): `OUTPOST_PI_DAEMON=1` → handler returns immediately.

## Acceptance criteria
- [ ] B1: two rapid agent_settled events → only one writes `.claimed` (O_EXCL) → only one SIGTERM.
- [ ] B2: `ctx.isIdle()=false` → handler defers (no SIGTERM, `_hotReloading` reset).
- [ ] B2: `_hotReloading=true` + `_deliverUserMessage` → message rejected with `recoverable: true`.
- [ ] B3: handler calls `process.kill(pid, "SIGTERM")` (not process.exit). Marker written before kill.
- [ ] B3: wrapper relaunches on exit 0 + marker; stops on exit 0 without marker; stops on non-zero.
- [ ] B4: `OUTPOST_PI_DAEMON=1` → handler returns immediately (no restart).
- [ ] B5: bash helper discovers PID from parent, reads nonce, writes armed file. Nonce mismatch → ignored.
- [ ] PID reuse: stale armed file with wrong nonce → ignored + unlinked.
- [ ] Toggle off: toggle absent + armed request → no restart.
- [ ] M3: request is PID-scoped + nonce-checked (NOT room-scoped, NOT _myRoomId).
- [ ] M5: identity/armed/claimed/marker files written with `mode: 0o600, flag: "wx"`.

## Files
- `pi-extension/src/index.ts` — runtime identity, arming command, agent_settled handler, quiescing gate
- `pi-extension/src/extension/composition_root.ts` — `_writeRuntimeIdentity()` call on session_start
- `pi-extension/src/extension.test.ts` — all acceptance criteria above
- `scripts/pi-restart-loop.sh` — marker-based handshake (delete exit-42/RESTART_ON_EXIT_ZERO)
- `scripts/hot-reload.sh` — revised `arm` (PID discovery + nonce), `off` globs cleanup

## Out of scope
- Lifecycle-fence hardening (M1 flush documentation, M2 user-message-during-restart documentation,
  nonce-file startup cleanup) → folded into acceptance criteria or a sibling story.
