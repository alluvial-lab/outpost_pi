# Session Note: 2026-07-31 — Hot-reload, pty-stall, tmux→Herdr migration

## Summary

A long session spanning five major arcs: (1) diagnosing and fixing the
"working" indicator stuck true, (2) discovering the code-server pty-stall
root cause (pi's stdout blocking on a stalled pts), (3) building the
extension hot-reload-via-process-restart feature (designed, reviewed twice
cross-model, implemented, tested end-to-end), (4) migrating from tmux to
Herdr for multi-session agent management, and (5) the relay auto-start fix.

102 commits. Two cross-model design reviews (gpt-5.6-sol). One feature
shipped through the full substrate lifecycle (scope → design → review →
implement → review → done).

## Arc 1: Working-flag fixes

### `story-fix-working-flag-stuck-after-session-shutdown` (done, `8b987c8`)
The mobile app showed pi as "working" after a session shutdown during an
active turn. Root cause: `resetTurnSnapshot()` was not called in
`disposeRuntimePorts` before `relay.stop()`. Fix: call it before the relay
closes so `working=false` is published while the relay is still connected.

### `story-fix-onconnected-clobbers-working-midturn` (done, `28dd6bd`)
The `c86bfb3` fix (publish `working=false` on `session_start` + a new
`onConnected` relay-reconnect callback) over-corrected: `onConnected`
hardcoded `publishWorking(false)`, clobbering a genuine `working=true`
during a relay reconnect mid-turn. Fix: publish the projection's actual
working value (`_turnProjection().working`) instead of hardcoded false.

### `c86bfb3` — session_start + onConnected
Publishes `working=false` on `session_start` (clears stale state if relay
already connected) and on relay `onConnected` (clears stale state from a
killed predecessor whose successor starts idle).

## Arc 2: Pty-stall diagnosis

### The problem
The operator observed that pi's turns didn't run unless they were actively
connected to code-server. When they disconnected, pi's event loop froze.

### Root cause (verified empirically)
pi (PID 3699086) had stdin/stdout/stderr wired to `/dev/pts/1`, a
pseudo-terminal whose master end was owned by **code-server's terminal
host**. pi is a Node.js TUI — its event loop is single-threaded. When
code-server stops draining the pty master (browser tab closed, machine
sleeps), the kernel pty buffer fills and `write()` blocks. One blocking
stdout write freezes the entire pi process.

Evidence: a 2-hour gap (22:12 → 00:19) with ZERO working updates while
pi's WebSocket to the relay stayed connected. pi resumed 29 seconds BEFORE
the app reconnected — proving the freeze was tied to the code-server pty,
not the app connection.

### Fix: tmux migration → Herdr migration
Initial fix: run pi under tmux (whose server drains the pty independently
of any client). Later migrated to Herdr (agent-aware multiplexer) for
multi-session management.

## Arc 3: Extension hot-reload via process restart

### The problem
pi's `/reload` does NOT re-import a `type: module` (ESM) extension.
Verified against jiti 2.7.0: the async import path uses
`nativeImport = (id) => import(id)` — Node's native dynamic `import()`,
whose ESM cache is **immutable at runtime**. `moduleCache: false` (which
pi sets) only clears CJS `require.cache`, not the ESM cache. A full
process restart is the only way to load new `dist/` code.

This made "working on outpost from outpost" (developing the extension via
the mobile app) impossible — every `dist/` change required a manual TUI
quit+relaunch, which can't be triggered from mobile.

### Design evolution (3 rounds of cross-model review)

**v1 (inline, rejected):** turn_end + machine-global sentinel + rename
claim + exit-42 + process.exit. Cross-model review (gpt-5.6-sol) found 5
blockers: rename isn't exclusive, agent_settled isn't a lock, exit-42
collides with daemon semantics, process.exit bypasses graceful lifecycle,
no concrete arming path.

**v2 design (rejected):** agent_settled + PID-scoped sentinel + rename
claim + exit-42. Second cross-model review found the same rename claim
bug, agent_settled isn't an exclusive lock, and exit-42 still collides.

**v2 revised (approved):** agent_settled + PID-scoped identity/nonce +
O_EXCL claim + quiescing gate + ctx.isIdle() recheck + graceful SIGTERM +
marker handshake. Third review: 4 blockers found, all fixed in-commit.

### Final architecture
- **Arming**: `/outpost-pi hot-reload arm` (TUI) or `./scripts/hot-reload.sh arm`
  (bash, walks ancestor chain for PID + reads nonce)
- **Restart boundary**: `agent_settled` (SDK's true idle — after ALL
  turns/retries/compactions/queued-followups settle). Handler is synchronous
  (no preempt), sets `_hotReloading` gate, rechecks `ctx.isIdle()`.
- **Quiescing gate**: rejects new messages as recoverable `delivery_error`
  (NOT `delivery_pending` — the process is exiting, replay is impossible)
- **Graceful shutdown**: `process.kill(pid, "SIGTERM")` → full session_shutdown
  path (working=false, relay drain). NOT process.exit.
- **Wrapper handshake**: exit 0 + `.restart-marker-<child-PID>` → relaunch;
  exit 0 no marker → stop; non-zero → stop
- **Daemon exclusion**: `OUTPOST_PI_DAEMON=1` → skip

### Feature lifecycle
- `feature-extension-hot-reload-via-process-restart`: scope → design →
  review (needs revision) → redesign → review (request changes, 4 blockers
  fixed) → done. 2 child stories. All findings preserved in the feature body.

### End-to-end test
Armed → agent_settled → SIGTERM → graceful shutdown → wrapper relaunch →
new pi loads fresh dist → relay auto-connects → app reconnects. Tested
twice successfully. ~2s relay-offline window.

## Arc 4: Relay auto-start fix (`aa856ab`)

### The problem
After every hot-reload restart (or any fresh pi process), the relay didn't
auto-connect. The `ensureStarted` gate used `_disposed` (starts `false` on a
fresh module), so it returned early and the relay never started. The operator
had to manually run `/outpost-pi` after every restart.

### Fix
Check `_state` instead of `_disposed`. If `_state` is not `"started"` (relay
not yet connected), auto-start. Covers both fresh processes and post-
replacement restarts. Skip only if already started.

## Arc 5: Herdr migration

### Motivation
tmux session management was painful throughout the session (dead sessions,
PATH issues, backgrounding bugs, stale processes). The operator runs 12
pi sessions across different project cwds and needs state visibility +
remote access.

### Herdr exploration
- Installed herdr v0.7.5 (single Rust binary)
- Cloned repo for source exploration
- Found native pi support (`src/detect/manifests/pi.toml` — detects
  "Working..." state)
- Found socket API (`pane.send_text`, `agent.start`, `agent.wait`) — key
  integration surface
- Found native pi session restore (integration v2: `pi --session <id>`)
- Gap: no auto-restart/respawn (wrapper still needed)

### Setup
- Created relay config (`.pi/outpost-pi/config.json`) for all 12 projects
- Created `scripts/herdr-setup.sh` (workspace creation) and
  `scripts/herdr-start-agents.sh` (agent startup)
- All 12 pi processes running under Herdr management
- outpost_pi under the wrapper (hot-reload support); others as managed agents
- Memory: 4.8GB used / 10GB available — comfortable

### Parked
`idea-herdr-symbiosis.md` — explore `pane.send_text` integration (replace
ensureStarted auto-start, replace bash-tool arm discovery), custom state
publishing, and the app-side room/project switcher for mobile access to
all 12 pis.

## Key decisions

- **`/reload` doesn't work for ESM extensions**: verified against jiti
  2.7.0 source. The ESM cache is immutable. Documented in AGENTS.md with
  the precise mechanism (not the stale hypotheses from the prior note).
- **agent_settled is the correct restart boundary**: it fires after ALL
  turns/retries/compactions/queued-followups settle, but is NOT an
  exclusive lock (ctx.isIdle() recheck + quiescing gate needed).
- **PID-scoped state, not room-scoped**: multi-pi is real and common.
  Each process reads only its own `.hot-reload-armed-<PID>`.
- **peers.lock contention is low**: reads don't lock; only the paired pi
  mutates for messages. 12 concurrent processes is fine.
- **Herdr over tmux**: agent state visibility, native pi detection, remote
  reattach, socket API. The wrapper coexists inside a Herdr pane.

## Operational state at session end

- **12 pi processes** under Herdr, all with relay config
- **outpost_pi** under the wrapper (`pi-restart-loop.sh`) — hot-reload active
- **Mobile app** connected and paired
- **Hot-reload toggle**: ON
- **Relay auto-start**: fixed (ensureStarted `_state` check)
- **All fixes in dist/**: rebuilt and live

## Commits
102 commits from `8b987c8` to `d4d5561`. Key:
- `c86bfb3` — working=false on session_start + onConnected
- `28dd6bd` — onConnected republishes authoritative projection (regression fix)
- `e678ac3` / `eee809a` — hot-reload v2 implementation
- `ec2908c` — hot-reload review fixes (B1-B4)
- `aa856ab` — relay auto-start on fresh process
- `8bc44f4` — pi foreground in wrapper (TUI fix)
- `d1773ed` — ancestor-chain PID discovery in arm script
- `867aecf` — herdr setup for all 12 projects

## Open items
- `idea-herdr-symbiosis` (backlog) — explore pane.send_text integration
- `feature-extension-hot-reload-via-process-restart` — done, 4 parked
  important findings (shell arming robustness, wrapper fs validation,
  subprocess tests, command error reporting)
- App-side room/project switcher — needed for mobile access to all 12 pis
- The `delivery_error` during restart window — app should resend on
  recoverable error (future app improvement)
