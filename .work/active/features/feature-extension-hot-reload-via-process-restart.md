---
id: feature-extension-hot-reload-via-process-restart
kind: feature
stage: drafting
tags: [pi-extension, workflow]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-30
updated: 2026-07-31
---

# Extension hot-reload via process restart (since `/reload` can't load ESM dist)

## Brief

pi's `/reload` does NOT re-import a `type: module` (ESM) extension. jiti's async
import path uses `nativeImport = (id) => import(id)` — Node's native dynamic
`import()` — whose ESM module cache is **immutable at runtime** (no API to
invalidate it). `moduleCache: false` (which pi sets) only clears the CJS
`require.cache`, not the ESM cache. So the only way to load new `dist/` code is a
full process restart.

This is operationally painful: the operator often works on Outpost-Pi *from*
Outpost-Pi (via the mobile app), and a full TUI quit+relaunch is tedious and
impossible to trigger from mobile mid-session. The feature goal: let the agent
(or operator) trigger a graceful process restart that preserves the session
(`pi --continue`), cleanly disconnects/reconnects the relay, and loads the new
`dist/` — without leaving the mobile operator stranded.

A first cut was built inline under operational pressure (commits `81f2df0`,
`150bab0`) and then put through an adversarial cross-model review
(`openai-codex/gpt-5.6-sol`). The review found **4 blockers** that require
rework before this is safe to use. This feature captures the redesign.

## Simplification opportunity

The inline `scripts/hot-reload.sh` + `scripts/pi-restart-loop.sh` + the
sentinel/toggle mechanism are a flawed first cut. The redesign should replace the
machine-global sentinel with a process-scoped request and a real restart
handshake, rather than layering patches on the broken protocol. The
`onConnected` working-flag fix (separate, tracked in
`story-fix-onconnected-clobbers-working-midturn`) ships independently.

## Adversarial review findings (must address before stage:done)

### Blockers

**B1. The restart can fire mid-turn (queued message or new prompt during the 500ms window).**
At `turn_end`, `_maybeDrainQueuedMessage()` runs BEFORE
`_maybeRestartForExtensionReload()`. If a queued message exists, it seeds a new
turn (`working=true`), then the restart timer arms → 500ms later SIGTERM kills
the new turn mid-response. This directly contradicts the "no cut-short turn"
guarantee. A new app prompt arriving during the 500ms window has the same
problem.
*Fix direction*: Do not restart from `turn_end` + fixed delay. Wait for an
`agent_settled` / idle boundary (no retry, compaction, steering, or follow-up
remaining). Investigate whether pi exposes such a hook; if not, the design must
define one or abandon the "no cut-short turn" claim and document the trade-off.

**B2. The sentinel is machine-global, not process-scoped.**
Every interactive pi AND every supervised daemon on the machine reads the same
`~/.pi/remote/.restart-pending`. Multi-pi is common (the operator runs outpost_pi
and patchbay concurrently). A daemon finishing first can consume the interactive
session's request; two processes can both pass `existsSync` and both schedule
SIGTERM. The sentinel must be process/session/room-scoped and atomically claimed
(rename-based claim, not existsSync+unlink which has a TOCTOU race).

**B3. The restart protocol cannot distinguish hot-reload from normal `/quit`.**
SIGTERM exits interactive pi with code 0. With `RESTART_ON_EXIT_ZERO=1` (the
documented config), a normal `/quit` or Ctrl+D relaunches pi immediately — the
operator cannot stop pi from inside the TUI. Without the wrapper at all, arming
the feature just kills pi (stranding a remote mobile operator). Exit code 42 is
documented but never used by this feature.
*Fix direction*: Establish an explicit wrapper/extension handshake. The
extension writes a restart-intent marker on hot-reload exit (distinct from
normal quit); the wrapper only relaunches on that marker. Normal `exit 0` must
stop the loop.

**B4. The 500ms delay is not a delivery guarantee.**
WebSocket `send()` only queues bytes; `ws.close()` doesn't await flush or the
close handshake before `process.exit(0)`. On a slow relay or flaky phone, 500ms
does not prove the final response or `working=false` reached the app.
*Fix direction*: Do not claim "response fully streams." Await extension outbound
drains + a bounded WebSocket flush/close contract, OR treat reconnect +
`session_sync` as the correctness path (the app rehydrates on reconnect) and
document that the final frame may be lost.

### Major

**M1. The restart timer is not lifecycle/generation-fenced.**
A `/reload`, `/new`, or resume during the 500ms delay sets `_disposed=true`, then
the successor's `session_start` resets it to false. The old timer now sees false
and kills the NEW session. Multiple arms can also leave multiple untracked timers.
*Fix*: store one owned restart timer, fence it to a runtime epoch/generation,
cancel on replacement/shutdown/superseding request.

**M2. Stale sentinel survives disable/re-enable cycles.**
`arm` while disabled warns but still creates the sentinel. `off` removes only the
toggle. Later `on` makes the old sentinel active → unexpected restart on the next
unrelated turn. A crash while toggle+sentinel are present has the same behavior on
the successor's first turn.
*Fix*: `arm` must fail when disabled; `off` must clear pending sentinels; bind
each request to a live instance/token with an expiry.

**M3. Messages can be dropped in the restart presence window.**
The app can still consider the room live just as pi disconnects. A message
written in that interval reaches the relay after the destination disappears; the
relay logs and drops it. Because the app classified it as "sent" (not "held"), it
is not resent on reconnect and becomes a visible timeout.
*Fix*: add a quiescing/restarting state broadcast BEFORE disconnect, or resend
all unconfirmed idempotent messages after reconnect.

**M4. `OUTPOST_PI_HOME` override weakens the local security boundary.**
The default `~/.pi/remote` is `0700`, but the advertised `OUTPOST_PI_HOME`
override uses `mkdir -p` without permission/owner/symlink validation. A
shared/attacker-writable override permits local restart DoS.
*Fix*: require owner-only directory, reject symlink/non-regular state files,
enforce `0700`/`0600`.

### Minor
- Tests cover only the easiest sentinel states. Missing: queued-message
  interleaving, `_disposed` reset on replacement, reconnect-mid-turn for
  `onConnected`, duplicate scheduling, unlink failure, multi-process, stale
  sentinel re-enable, wrapper exit behavior.
- `onConnected` has no direct working-state contract test (reconnect while
  `working=true`).
- Comments overstate behavior ("fully streams" is unproven; exit 42 described but
  not wired).
- Redundant `working=false` publish on shutdown (`resetTurnSnapshot` + `_goIdle`
  both publish).

## Current state (inline, pre-redesign)
- `scripts/pi-restart-loop.sh` — wrapper loop (needs handshake per B3)
- `scripts/hot-reload.sh` — toggle manager (needs scoping per B2, M2)
- `pi-extension/src/index.ts` — `_maybeRestartForExtensionReload()` + sentinel
  paths (needs agent_settled per B1, lifecycle fence per M1)
- The inline commits (`81f2df0`, `150bab0`) are NOT reverted — they're a flawed
  first cut that the redesign will replace or substantially rewrite. Keeping them
  lets a resumed session see the current state. The toggle defaults to OFF, so the
  broken behavior is inert until explicitly enabled.

## Design decisions (resolves the open questions)

- **Q1 (agent_settled boundary)**: pi DOES expose `agent_settled`. It fires in the `finally` of `_runAgentRun()` (agent-session.js:755) — AFTER the `prompt` + `continue()` loop exits, meaning all retries, compactions, and follow-up turns have genuinely settled. `turn_end` fires per-turn; `agent_settled` fires once when the whole agent run is done. This is the correct restart boundary — it eliminates B1 (the queued-message race) entirely because no follow-up turn can be in-flight at `agent_settled` time. The extension hooks `ownerPi.on("agent_settled", ...)`.
- **Q2 (RPC-vs-sentinel)**: Neither. The mechanism stays a filesystem sentinel but is made **process-scoped** by keying on the relay room (each pi's room is unique per cwd). The sentinel filename includes the room id, so the outpost pi and the patchbay pi read different files. This solves B2 (machine-global) without adding an IPC surface. Atomic claim via `rename(2)` (not `existsSync`+`unlink`, which is TOCTOU-racy).
- **Q3 (supervisor-vs-wrapper)**: Use the existing `scripts/pi-restart-loop.sh` wrapper (interactive pi needs the TUI; the supervisor only spawns headless `--mode rpc` children). The wrapper handshake uses exit code `42` — which is ALREADY defined (`EXIT_DAEMON_FRESH_SESSION = 42`) and ALREADY handled by the supervisor as "intentional recycle, restart immediately, don't burn crash backoff." The wrapper adopts the same semantics: exit 42 → relaunch; exit 0 → stop; non-zero → stop (crash safety). This solves B3 (ambiguous exit protocol) with an established code.

## Architectural choice

**Filesystem sentinel keyed by relay room + `agent_settled` boundary + exit-42 restart handshake.**

The inline first cut had the right shape (sentinel + wrapper) but wrong details (turn_end + machine-global sentinel + `RESTART_ON_EXIT_ZERO`). The redesign fixes all three seams:

1. **Restart trigger moves from `turn_end` → `agent_settled`**: eliminates B1 (no turn can be in-flight at agent_settled time). Removes the 500ms delay entirely — `agent_settled` IS the "response fully streamed" boundary, so no timer is needed.
2. **Sentinel becomes room-scoped**: `<REMOTE_DIR>/.restart-pending-<roomId>` instead of a single machine-global file. Atomic claim via `fs.renameSync(guardFile, sentinel)` — `rename` is atomic on POSIX, so exactly one process wins the claim even if both see the guard.
3. **Exit handshake uses code 42**: the wrapper relaunches only on 42 (established `EXIT_DAEMON_FRESH_SESSION` semantics); normal `exit 0` (`/quit`, Ctrl+D) stops the loop. No more `RESTART_ON_EXIT_ZERO`.

## Implementation Units

### Unit 1: `agent_settled` restart hook + room-scoped sentinel
**File**: `pi-extension/src/index.ts`
**Story**: `feature-extension-hot-reload-via-process-restart-agent-settled-hook`

Replace the `turn_end`-based `_maybeRestartForExtensionReload()` with an `agent_settled` handler. The sentinel becomes room-scoped.

```typescript
// The restart request is room-scoped so multi-pi (outpost + patchbay) don't
// contend on one machine-global file. Keyed on the relay room, which is unique
// per cwd.
function _restartPendingSentinelPath(): string {
  const base = process.env["OUTPOST_PI_HOME"] || join(homedir(), ".pi", "remote");
  // _myRoomId is the relay room this pi authenticated in; null before connect.
  return _myRoomId ? join(base, `.restart-pending-${_myRoomId}`) : null!;
}

// Atomic claim: rename a guard file into the sentinel path. rename(2) is atomic
// on POSIX — exactly one caller wins even if two see the guard. The losing
// caller's rename throws ENOENT (guard already moved) → caught, no restart.
function _claimRestartRequest(): boolean {
  const sentinel = _restartPendingSentinelPath();
  if (!sentinel) return false;
  const guard = `${sentinel}.guard.${process.pid}`;
  try {
    writeFileSync(guard, "");
    renameSync(guard, sentinel);  // atomic on POSIX
    return true;
  } catch {
    try { unlinkSync(guard); } catch { /* best-effort */ }
    return false;
  }
}

// Hooks agent_settled (fires after ALL turns/retries/compactions settle — the
// true idle boundary). No timer needed: agent_settled IS the flush boundary.
ownerPi.on("agent_settled", () => {
  if (!existsSync(_hotReloadEnabledPath())) return;  // persistent toggle
  if (!_claimRestartRequest()) return;  // no request for THIS room
  // Exit with the established "intentional recycle" code. The wrapper restarts.
  process.exit(EXIT_HOT_RELOAD_RESTART);
});
```

**Implementation Notes**:
- `EXIT_HOT_RELOAD_RESTART = 42` — reuse the existing `EXIT_DAEMON_FRESH_SESSION` constant (same value, same supervisor semantics). Export it from `daemon/rpc_child.ts` or alias it.
- The toggle (`.hot-reload-enabled`) stays machine-global — it's a deliberate opt-in, not per-room. The REQUEST is per-room.
- `_myRoomId` is set during `_startRelayViaTransport`; before that, the sentinel path is null and the hook no-ops.
- No `setTimeout` — `agent_settled` already means the response streamed. This removes M1 (untracked timer) entirely.

**Acceptance Criteria**:
- [ ] Restart fires at `agent_settled`, NOT `turn_end` — a queued follow-up turn is NOT cut short (the hook fires only after the follow-up settles).
- [ ] Sentinel is room-scoped: outpost pi (room A) and patchbay pi (room B) read different files.
- [ ] Atomic claim: two processes cannot both restart from one sentinel.
- [ ] Toggle off + sentinel present → no restart (sentinel ignored).
- [ ] Exit code is 42, not 0.

---

### Unit 2: Wrapper handshake (exit 42 relaunch, exit 0 stops)
**File**: `scripts/pi-restart-loop.sh`
**Story**: (same story — the wrapper + hook ship together)

Replace the `RESTART_ON_EXIT_ZERO` logic with exit-code discrimination:

```bash
while true; do
  set +e; pi --continue; exit_code=$?; set -e
  if [ "$exit_code" -eq 42 ]; then
    sleep 1; continue          # intentional hot-reload restart
  fi
  if [ "$exit_code" -eq 0 ]; then
    break                       # normal /quit, Ctrl+D — stop
  fi
  break                         # crash (non-zero) — stop, don't loop
  fi
done
```

**Implementation Notes**:
- Removes `RESTART_ON_EXIT_ZERO` entirely — exit 0 always stops.
- Exit 42 is the ONLY restart trigger. This means `/quit` from the TUI stops the loop (operator can actually quit).
- Crash safety: non-zero, non-42 exits stop the loop (no auto-restart loops on crash — the supervisor does that for daemons; the interactive wrapper doesn't).

**Acceptance Criteria**:
- [ ] Exit 42 → relaunch `pi --continue`.
- [ ] Exit 0 (`/quit`) → stop (no relaunch).
- [ ] Non-zero non-42 (crash) → stop.

---

### Unit 3: `hot-reload.sh` arm uses room-scoped sentinel
**File**: `scripts/hot-reload.sh`
**Story**: (same story)

The `arm` command can't know the room id (it's a shell script, not the extension). Two options:
- **Option A**: `arm` writes a guard file per running pi by querying the relay (overkill for a shell script).
- **Option B** (chosen): `arm` writes a generic `.restart-pending-requested` marker; each pi's `agent_settled` hook checks for BOTH its room-scoped sentinel AND a generic "any room" request. Simpler: the agent (via the bash tool) writes the room-scoped sentinel directly since it knows its own room.

Chosen: **the agent writes the sentinel directly** (it knows `_myRoomId` via the extension's state). `hot-reload.sh arm` becomes a convenience that writes a generic request resolved at hook time, OR the agent calls a new `/outpost-pi hot-reload arm` command. Keep `hot-reload.sh` for `on`/`off`/`status` only; `arm` moves to an extension command or the agent's bash tool.

**Acceptance Criteria**:
- [ ] `arm` writes a request that only the CURRENT pi's room consumes.
- [ ] `off` clears ALL pending sentinels (glob `.restart-pending-*`).
- [ ] `status` shows per-room state.

---

### Unit 4: Lifecycle fence + M2/M4 fixes
**File**: `pi-extension/src/index.ts`, `scripts/hot-reload.sh`
**Story**: `feature-extension-hot-reload-via-process-restart-lifecycle-fence`

- **M1 (timer not fenced)**: eliminated — no timer (agent_settled is synchronous, fires once). The only lifecycle concern is a session replacement between `agent_settled` and `process.exit(42)` — guard with `_disposed` (if replaced mid-hook, don't exit; the successor will pick up the next request).
- **M2 (stale sentinel)**: `off` globs and removes `.restart-pending-*`. The toggle-off check at hook time means a sentinel without the toggle is ignored.
- **M3 (dropped messages)**: document that the app rehydrates via `session_sync` on reconnect; the restart window is ~2s. No quiescing state in v1 (out of scope — the session_sync path is the correctness backstop).
- **M4 (OUTPOST_PI_HOME perms)**: validate the dir is `0o700` owner-only at hook time; reject symlink/non-regular sentinel files.

**Acceptance Criteria**:
- [ ] `_disposed` guard prevents exit if session replaced mid-hook.
- [ ] `off` removes all pending sentinels.
- [ ] Symlink sentinel files are rejected.

---

## Implementation Order
1. Unit 1 + Unit 2 (the hook + wrapper handshake — ship together, since the wrapper must understand exit 42 for the hook to work)
2. Unit 3 (hot-reload.sh arm refinement)
3. Unit 4 (lifecycle fence + M2/M4 hardening)

## Simplification
- **Delete**: `RESTART_ON_EXIT_ZERO` env var and its logic in `pi-restart-loop.sh` (replaced by exit-42 discrimination).
- **Delete**: the `turn_end`-based `_maybeRestartForExtensionReload()` and its 500ms `setTimeout` (replaced by `agent_settled`).
- **Delete**: the machine-global `.restart-pending` sentinel path (replaced by room-scoped).
- **Retain**: the `.hot-reload-enabled` toggle (machine-global deliberate opt-in is correct).
- **Retain**: `scripts/hot-reload.sh` for `on`/`off`/`status` (the `arm` subcommand moves to an extension command or the bash tool).

## Testing
- **Regression test (B1)**: seed a turn + a queued follow-up → `agent_settled` fires only after BOTH settle → restart happens after the follow-up, not mid-turn. (The old `turn_end` + 500ms code would cut short the follow-up; verify the new code doesn't.)
- **Contract test (B2)**: two rooms (outpost + patchbay) → arm outpost's room → only outpost restarts.
- **Atomic claim test (B2)**: two processes race the rename → exactly one wins.
- **Exit-code test (B3)**: `process.exit(42)` → wrapper relaunches; `process.exit(0)` → wrapper stops.
- **Toggle-off test (existing)**: toggle off + sentinel → no restart.
- **Lifecycle fence test (M1)**: session replacement between `agent_settled` and exit → no exit (successor survives).

## Risks
- **`agent_settled` timing**: if the SDK ever changes `agent_settled` to fire before the response fully flushes to the relay, the "no cut-short turn" guarantee breaks. Mitigation: the relay's `send()` is synchronous-queueing; `agent_settled` fires after the agent loop, by which point all frames are queued. Low risk.
- **`_myRoomId` null before connect**: if `agent_settled` fires before the relay connects (theoretical), the sentinel path is null and the hook no-ops. Safe — no spurious restart.
- **Multi-pi with the SAME room**: if two pi processes auth to the same room (the multi-pi hazard), the room-scoped sentinel doesn't disambiguate them. This is the existing `peers.lock` contention hazard — out of scope (documented in AGENTS.md as a single-identity constraint).

## Cross-model design review (2026-07-31, gpt-5.6-sol) — design needs revision

Verdict: **design needs revision.** The core direction is promising
(`agent_settled` > `turn_end`; room/process scoping is necessary; explicit
handshake > restart-on-every-clean-exit) but the three central design claims
are overstated. Do NOT implement as written.

### Verified claims

- **`agent_settled` is a better boundary than `turn_end`**: TRUE that it fires
  after Pi drains its continuation queue (retries, compaction, queued
  follow-ups). But it is NOT an exclusive lock — `_isAgentRunActive` is set false
  BEFORE extension handlers run, so a new run can start mid-handler. And it does
  NOT await Outpost-Pi's async outbound transport (secure-channel sealing, WS
  send). So "agent_settled IS the flush boundary" is false.
- **Room sentinel + atomic rename**: FALSE. `rename(guard, sentinel)` is not an
  exclusive claim — POSIX `rename(old, existingDest)` atomically *replaces* the
  destination, so two processes each writing their own guard and renaming it
  over the same destination BOTH succeed. The "loser gets ENOENT" assertion is
  wrong. Need `O_CREAT|O_EXCL` (exclusive create) instead.
- **Exit 42 is a safe handshake**: FALSE. 42 means "fresh session, drop
  `--continue`" in the daemon supervisor, NOT "restart with --continue". And
  direct `process.exit(42)` bypasses graceful shutdown entirely (no
  session_shutdown, no working=false, no relay drain).

### Blockers found

- **B1**: the proposed atomic claim lets every contender win (rename is not
  compare-and-swap). Use `O_CREAT|O_EXCL`.
- **B2**: `agent_settled` still permits a new run before the restart handler
  exits (`_disposed` tracks session replacement, not new runs). Need a
  synchronous quiescing ingress gate + `ctx.isIdle()` recheck.
- **B3**: `process.exit(42)` bypasses the graceful lifecycle (no
  session_shutdown, no working=false, no relay drain). Must trigger Pi's
  SIGTERM/shutdown path with a durable wrapper-consumed restart marker.
- **B4**: exit 42 collides with daemon fresh-session semantics — would rotate
  daemons to fresh sessions. Must explicitly disable in `OUTPOST_PI_DAEMON=1`
  mode or use a distinct protocol.
- **B5**: no concrete way to arm the correct room — the shell script can't know
  `_myRoomId` (internal runtime state; assigned name can be `name#2`). Arming
  must be an extension-owned command.

### Majors found

- M1: `agent_settled` is not an outbound-delivery flush boundary.
- M2: `session_sync` can't recover a user message Pi never accepted (input sent
  during the quiesce window is lost, not replayed). Need ack/resend or a
  quiescing presence state.
- M3: `_myRoomId` is not a safe lifecycle token (stale after replacement, never
  reset to null). Bind to runtime epoch/lease, not the mutable string.
- M4: same-room multi-Pi isn't harmlessly out of scope (mixed extension versions
  after one restarts). Need process-instance scoping or duplicate-ownership
  detection.
- M5: filesystem perm checks remain TOCTOU-prone. Use `O_NOFOLLOW`, `O_EXCL`,
  `fstat` on the opened fd, owner-uid check.

### Revision direction (from reviewer)

1. Extension-owned, process/runtime-scoped arming command (not a shell script
   guessing the room).
2. Real exclusive claim primitive (`O_CREAT|O_EXCL`, not rename).
3. Synchronous quiescing ingress gate + `ctx.isIdle()` recheck (not just
   `_disposed`).
4. Graceful Pi shutdown (trigger SIGTERM, not direct `process.exit`) + a
   durable wrapper-consumed restart marker (not the exit code).
5. Explicit daemon exclusion (don't run the hook in `OUTPOST_PI_DAEMON=1`).
6. Bounded owner-channel drain + honest reconnect guarantees.
7. Acknowledgment/resend or quiescing for user messages during restart.

Stage rolled back to `drafting` pending revision. The child stories are also
back at `drafting` (their design depends on the revised approach).
