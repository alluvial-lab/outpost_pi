---
id: feature-extension-hot-reload-via-process-restart
kind: feature
stage: done
tags: [pi-extension, workflow]
parent: null
depends_on: []
release_binding: v0.4.0
gate_origin: null
created: 2026-07-30
updated: 2026-08-11
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

## Revised design (2026-07-31, post-review) — addresses all 5 blockers + 5 majors

### Architectural choice

**PID-scoped request + nonce + `agent_settled` quiescing gate + graceful SIGTERM + wrapper-consumed restart marker.**

The reviewer disproved the prior design's three pillars (rename-as-exclusive-claim, exit-42 handshake, agent_settled-as-flush-boundary). The revised design replaces all three:

- **Arming**: the extension writes a `.runtime-self-<PID>` identity file on `session_start` (PID + nonce + epoch). The operator arms via `/outpost-pi hot-reload arm`; the agent (via bash) arms via `scripts/hot-reload.sh arm` which discovers the PID from the bash parent chain + reads the nonce. The armed request is PID-scoped (`.hot-reload-armed-<PID>`) with the nonce embedded, so multi-pi can't cross-fire and PID reuse is detected.
- **Exclusive claim**: `O_CREAT|O_EXCL` on a `.claimed-<PID>` file — exactly one `agent_settled` wins (prevents double-restart from a follow-up turn). The armed file is then unlinked.
- **Quiescing gate + idle recheck**: the `agent_settled` handler runs synchronously (no `await`), so no new run can start mid-handler. After setting a `_hotReloading` flag, it rechecks `ctx.isIdle()` (available to extension handlers via runner.js:497). If a run somehow started (it can't during a sync handler, but the gate covers the post-handler pre-SIGTERM window), the request is deferred.
- **Graceful shutdown**: `process.kill(process.pid, "SIGTERM")` — NOT `process.exit()`. Pi's SIGTERM handler fires `session_shutdown` → `resetTurnSnapshot` (working=false) → bounded owner-channel drain → `relay.stop()` → `process.exit(0)`. The graceful path runs in full.
- **Wrapper handshake**: the extension writes a durable `.restart-marker` BEFORE SIGTERM. The wrapper checks for it after `exit 0`: present → relaunch `pi --continue`; absent → stop. Normal `/quit` exits 0 without the marker → wrapper stops. Exit code is always 0 (no 42 collision).
- **Daemon exclusion**: `if (process.env.OUTPOST_PI_DAEMON === "1") return;` at the top of the handler — daemons never hot-reload via this path.

### Unit 1: Runtime identity + arming

**File**: `pi-extension/src/index.ts`

On `session_start`, the extension writes its identity so the bash-tool arming path can target it:

```typescript
const _hotReloadNonce = randomUUID();

// Written on session_start (after epoch is claimed). Per-PID so multi-pi don't
// clobber each other. Contains the nonce for PID-reuse protection.
function _writeRuntimeIdentity(): void {
  if (process.env["OUTPOST_PI_DAEMON"] === "1") return; // daemons excluded
  const dir = _outpostPiRemoteDir();
  const path = join(dir, `.runtime-self-${process.pid}`);
  writeFileSync(path, JSON.stringify({ pid: process.pid, nonce: _hotReloadNonce, ts: Date.now() }), { mode: 0o600 });
}
```

The `/outpost-pi hot-reload arm` command (operator, TUI) writes the armed request directly:

```typescript
function _armHotReload(): void {
  if (process.env["OUTPOST_PI_DAEMON"] === "1") return;
  if (!existsSync(_hotReloadEnabledPath())) {
    _notify("[outpost-pi] hot-reload toggle is off — run /outpost-pi hot-reload on first", "warning");
    return;
  }
  const dir = _outpostPiRemoteDir();
  const armed = join(dir, `.hot-reload-armed-${process.pid}`);
  writeFileSync(armed, JSON.stringify({ nonce: _hotReloadNonce, ts: Date.now() }), { mode: 0o600, flag: "wx" }); // O_CREAT|O_EXCL
  _notify(`[outpost-pi] hot-reload armed — restart fires at next agent_settled (pid=${process.pid})`, "info");
}
```

### Unit 2: `agent_settled` handler (quiescing gate + graceful SIGTERM)

**File**: `pi-extension/src/index.ts`

```typescript
let _hotReloading = false;

ownerPi.on("agent_settled", (_event, ctx) => {
  // B4: daemon exclusion — daemons use the supervisor's own restart path.
  if (process.env["OUTPOST_PI_DAEMON"] === "1") return;
  // Toggle gate — persistent opt-in.
  if (!existsSync(_hotReloadEnabledPath())) return;

  const armedPath = join(_outpostPiRemoteDir(), `.hot-reload-armed-${process.pid}`);
  if (!existsSync(armedPath)) return;

  // Verify nonce (PID-reuse protection). Read + compare synchronously.
  let request: { nonce?: string; ts?: number };
  try { request = JSON.parse(readFileSync(armedPath, "utf8")); } catch { return; }
  if (request.nonce !== _hotReloadNonce) return; // stale (PID reused) or wrong process
  // Expiry: ignore requests older than 5 minutes (stale from a crashed run).
  if (typeof request.ts === "number" && Date.now() - request.ts > 5 * 60_000) {
    try { unlinkSync(armedPath); } catch { /* best-effort */ }
    return;
  }

  // B2: quiescing gate. Set BEFORE the idle recheck so any message arriving
  // between this handler returning and SIGTERM firing is rejected (retryable)
  // by _deliverUserMessage, not silently started as a new turn.
  _hotReloading = true;

  // B2: idle recheck. agent_settled fires when the agent loop is done, but
  // _isAgentRunActive is set false BEFORE extension handlers run. A synchronous
  // handler can't be preempted, but ctx.isIdle() is the authoritative check.
  if (!ctx.isIdle()) {
    _hotReloading = false; // a run started — defer to next agent_settled
    return;
  }

  // B1: exclusive claim via O_CREAT|O_EXCL. Prevents a follow-up turn's
  // agent_settled from double-triggering (shouldn't happen with the gate, but
  // belt-and-suspenders).
  const claimedPath = join(_outpostPiRemoteDir(), `.claimed-${process.pid}`);
  try { writeFileSync(claimedPath, "", { mode: 0o600, flag: "wx" }); }
  catch { _hotReloading = false; return; } // already claimed

  // Consume the armed request.
  try { unlinkSync(armedPath); } catch { /* best-effort */ }

  // B3: durable restart marker for the wrapper (NOT exit code 42).
  const markerPath = join(_outpostPiRemoteDir(), ".restart-marker");
  try { writeFileSync(markerPath, String(process.pid), { mode: 0o600 }); } catch { /* best-effort */ }

  // B3: graceful shutdown via SIGTERM (NOT process.exit). Pi's SIGTERM handler
  // fires session_shutdown → resetTurnSnapshot (working=false) → bounded owner
  // drain → relay.stop → process.exit(0). The handler returns first; SIGTERM
  // fires on the next event-loop tick.
  process.kill(process.pid, "SIGTERM");
});
```

The quiescing gate in the ingress path:

```typescript
// In _deliverUserMessage, at the top:
if (_hotReloading) {
  _sendDeliveryError(sender, msg.id, "agent is restarting for extension hot-reload", /* recoverable */ true);
  return;
}
```

### Unit 3: Wrapper handshake (marker, not exit code)

**File**: `scripts/pi-restart-loop.sh`

```bash
REMOTE_DIR="${OUTPOST_PI_HOME:-$HOME/.pi/remote}"
MARKER="$REMOTE_DIR/.restart-marker"

while true; do
  set +e; pi --continue; exit_code=$?; set -e
  # Graceful exit (SIGTERM or /quit). Check for the restart marker.
  if [ "$exit_code" -eq 0 ] && [ -f "$MARKER" ]; then
    rm -f "$MARKER"
    sleep 1; continue          # hot-reload restart
  fi
  # Any other exit (0 without marker, crash, signal) → stop.
  break
done
```

Exit code 42 is NOT used. Normal `/quit` → exit 0, no marker → stop. Hot-reload → SIGTERM → exit 0 + marker → relaunch. Crash → non-zero → stop.

### Unit 4: `scripts/hot-reload.sh` (revised)

**File**: `scripts/hot-reload.sh`

- `on` / `off` / `status`: unchanged (manage the persistent toggle).
- `arm`: discovers the pi PID from the bash parent chain, reads the nonce from `.runtime-self-<PID>`, writes `.hot-reload-armed-<PID>` with the nonce. Fails if the toggle is off or no identity file exists.

```bash
arm() {
  local pid nonce identity
  pid=$(ps -o ppid= -p $$ | tr -d ' ')           # bash parent = pi
  identity="$REMOTE_DIR/.runtime-self-$pid"
  [ -f "$identity" ] || { echo "[hot-reload] no runtime identity for pid=$pid — is pi running?" >&2; exit 1; }
  nonce=$(python3 -c "import json; print(json.load(open('$identity'))['nonce'])")
  [ -f "$TOGGLE" ] || { echo "[hot-reload] toggle is off — run 'hot-reload.sh on' first" >&2; exit 1; }
  printf '{"nonce":"%s","ts":%s}' "$nonce" "$(date +%s)" > "$REMOTE_DIR/.hot-reload-armed-$pid"
  echo "[hot-reload] armed for pid=$pid — restart at next agent_settled"
}
```

### M1–M5 handling

- **M1 (agent_settled not a flush boundary)**: the SIGTERM path runs `session_shutdown` → `disposeRuntimePorts` → `resetTurnSnapshot` + `relay.stop()`. The existing owner-channel detach + relay drain provide a bounded flush. The honest guarantee: "the response is handed to the relay before disconnect; end-to-end receipt is NOT acknowledged — the app rehydrates via session_sync on reconnect." Documented, not claimed as flush.
- **M2 (user message during restart window lost)**: the quiescing gate rejects messages with `recoverable: true` AFTER the handler sets `_hotReloading`. Messages arriving BEFORE the gate (in-flight when agent_settled fired) are already being processed. The restart window is ~2s; the app's reconnect logic + session_sync recover output. Input sent during the window is best-effort — documented as a known v1 limitation.
- **M3 (_myRoomId not safe)**: the request is PID-scoped + nonce-checked, NOT room-scoped. `_myRoomId` is not used. PID + nonce + epoch are the identity. The nonce is generated at module load and never changes within a process lifetime.
- **M4 (same-room multi-pi)**: PID-scoping means each process reads only its own `.hot-reload-armed-<PID>`. Two processes in the same room can't cross-fire. If both arm, both restart independently — documented as acceptable (each process reloads its own dist/).
- **M5 (TOCTOU perms)**: the identity/armed/claimed/marker files are written with `mode: 0o600` and `flag: "wx"` (O_CREAT|O_EXCL|O_NOFOLLOW equivalent). The dir is validated as `0o700` owner-only on first write. `readFileSync` of the armed file reads the content atomically enough for the nonce check; a swap between read and unlink would at worst cause a double-check (harmless with the claim gate).

### Implementation Order
1. Unit 1 (runtime identity + arming command + bash helper) + Unit 3 (wrapper) — ship together; the wrapper must understand the marker for the handler to work.
2. Unit 2 (agent_settled handler + quiescing gate + graceful SIGTERM) — the core restart logic.
3. Unit 4 (hot-reload.sh arm revision).

### Testing
- **B1 (exclusive claim)**: two rapid agent_settled events → only one writes the `.claimed` file (O_EXCL) → only one SIGTERM.
- **B2 (idle recheck)**: mock ctx.isIdle()=false → handler defers (no SIGTERM, `_hotReloading` reset).
- **B2 (quiescing gate)**: `_hotReloading=true` + `_deliverUserMessage` → message rejected with `recoverable: true`.
- **B3 (graceful SIGTERM)**: handler calls `process.kill(pid, "SIGTERM")` (mock), NOT `process.exit`. Marker file written before the kill.
- **B4 (daemon exclusion)**: `OUTPOST_PI_DAEMON=1` → handler returns immediately.
- **B5 (arming)**: bash helper discovers PID from parent, reads nonce, writes armed file. Nonce mismatch → handler ignores.
- **PID reuse**: stale armed file with wrong nonce → ignored + unlinked.
- **Wrapper**: exit 0 + marker → relaunch; exit 0 no marker → stop; non-zero → stop.
- **Toggle off**: toggle absent + armed request → no restart.

### Risks
- **agent_settled timing**: if the SDK changes agent_settled to fire before the agent loop drains, the quiescing gate + ctx.isIdle() recheck are the safety net. Low risk (SDK contract).
- **Nonce file cleanup**: `.runtime-self-<PID>` files accumulate. Add a startup sweep that removes identity files for PIDs that no longer exist (`kill -0 <PID>` probe). Minor.
- **User messages during the ~2s restart window**: documented as a v1 limitation. The app's reconnect + session_sync recover output; input is best-effort. A future app-side "restarting" presence state would close this fully.


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

## Implementation summary (2026-07-31)

Both child stories implemented and verified:
- `story-hot-reload-agent-settled-hook-and-wrapper` (done, `e678ac3`): runtime identity, PID-scoped arming, agent_settled handler with quiescing gate + ctx.isIdle() recheck, exclusive O_EXCL claim, graceful SIGTERM + marker, wrapper handshake.
- `story-hot-reload-lifecycle-fence` (done, `eee809a`): _disposed guard at multiple checkpoints, secure filesystem validation (lstat owner+mode+symlink rejection), stale identity sweep, off-cleanup glob.

### Verification
- 962 tests passed, 3 skipped (7 new tests for the v2 hot-reload mechanism)
- Typecheck + build green
- Scripts pass `bash -n`
- The v1 code (turn_end sentinel, machine-global files, RESTART_ON_EXIT_ZERO, exit-42) is fully replaced
- The onConnected working-flag fix (`_turnProjection().working`) is preserved

### Key implementation decisions
- The quiescing gate sends `delivery_pending` (recoverable), not a hard error — the app resends on reconnect.
- The `_disposed` flag is rechecked at 4 points in the handler (after gate set, after claim, after marker, before kill) to handle session replacement mid-handler.
- The marker write uses `flag: "wx"` (O_CREAT|O_EXCL) — if a stale marker exists, it's validated (owner-only regular file) and removed before the new write.
- `_secureHotReloadRemoteDir()` validates the OUTPOST_PI_HOME dir is owner-only 0o700 before any file operation.
- Stale identity sweep (`_sweepStaleRuntimeIdentities`) removes `.runtime-self-<PID>` files for PIDs that no longer exist, preventing accumulation.

## Review record (2026-07-31, standard weight, gpt-5.6-sol cross-model)

**Pass 1 verdict**: Request changes — 4 blockers found.

**Blockers fixed (commit ec2908c)**:
- B1: quiescing gate delivery_pending → delivery_error (recoverable) — no false replay promise
- B2: marker PID-scoped (.restart-marker-<PID>) + wrapper validates child PID
- B3: /outpost-pi hot-reload off globs all PID-scoped state via readdirSync
- B4: AGENTS.md updated to v2 protocol (removed all v1 references)

**Important findings parked** (unbound, non-blocking):
- Shell arming PPID assumption (walk ancestor chain for robustness) — I1
- Wrapper filesystem security validation — I2
- Subprocess tests for wrapper/helper — I3
- Command error misreporting — I4

**Closure**: standard weight — one pass, receiver-confirmed blockers fixed + verified, closed without another independent pass. 962 tests green.
