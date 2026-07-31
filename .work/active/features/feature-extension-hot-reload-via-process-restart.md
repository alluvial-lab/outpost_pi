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
updated: 2026-07-30
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

## Open design questions (for feature-design)
1. Does pi expose an `agent_settled` / idle boundary the extension can hook, or
   must the restart be deferred to the next genuine idle (turn_end with no queued
   message + no pending follow-up)? This determines whether the "no cut-short
   turn" guarantee is achievable or must be downgraded to "best-effort, may cut
   short a queued follow-up."
2. Should the restart request be an extension command (RPC from the agent's bash
   tool to the extension via a UDS/IPC) rather than a filesystem sentinel? This
   would solve B2 (process-scoped by construction) and M1 (lifecycle-owned by the
   extension) at once, but adds an IPC surface.
3. Is the restart-loop wrapper even the right architecture, or should this use the
   existing outpost-pi supervisor (`src/daemon/supervisor.ts`) extended to manage
   an interactive (not just RPC) child? The supervisor already does auto-restart
   with backoff and process-scoped tracking.
