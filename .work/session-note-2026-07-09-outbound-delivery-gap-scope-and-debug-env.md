---
id: session-note-2026-07-09-outbound-delivery-gap-scope-and-debug-env
created: 2026-07-09
updated: 2026-07-09
tags: [pi-extension, relay, app, lifecycle, workflow]
---

# Session note — outbound delivery gap, scope, and the debug-env dead end

## Context in

Operator reported a mobile turn was not received. Stated a new sandbox config
was under test. After the first diagnosis turn, asked to **scope option 2**
(outbound store-and-forward), then to find the export command + config location
for the extension debug log. Final ask: session note + verify whether the
story filed in the `skills/` repo (`feature-pi-sandbox-env-add-config`) solves
the debug-env use case, before restarting the session to pick up pi + model
upgrades.

## What shipped this session

### 1. Diagnosed the mobile delivery gap (live relay log)

Root cause of the missed turn: **Pi→app is best-effort, fire-and-forget; the
relay drops frames for an absent app peer, and nothing auto-backfills.**

Relay log evidence (2026-07-09 ~14:34): ~18 frames from this Pi (`l2X/dUc=`)
to the app peer (`dpOPIdc=`) were dropped with
`WARN dest (peer, room) not found, dropping … bytes=225460` (a full turn among
them). The app only re-authenticated ~8s later at 14:34:43, then re-authed
again at 14:39:23 with `superseded_existing:true` — reconnect churn.

Two distinct drop windows identified:
- **Known-offline window** — extension knows the peer is gone (`peer_offline`
  received) but `broadcast()` drops, not buffers.
- **Detection-lag window** — frames sent *before* `peer_offline` arrives (the
  8s gap above); the relay has no route, the extension hasn't been told.

Code-confirmed mechanism:
- `peer_online`/`peer_offline` ARE consumed: `index.ts:331-342` →
  `owner_multiplexer.markPeerOffline/Online`.
- `broadcast()` (`owner_multiplexer.ts:450`) is the drop site:
  `if (this.offlinePeerIds.has(peerId)) continue;` — suspends fan-out for a
  known-offline peer but **drops the frame, no buffer**.
- Inbound (app→Pi) HAS a bounded replay queue (max 2, overflow →
  `internal_error`) via `feature-session-stable-message-delivery`. Outbound
  has no equivalent — the asymmetry.
- App reconnect does NOT auto-pull transcript: `requestResumeHydration()` only
  rehydrates presence + rooms, not `session_sync`. So dropped turns need manual
  refresh to recover.

### 2. Scoped `feature-outbound-buffer-on-peer-offline` (commit bb08d91)

- **2a (shipped to active, drafting)** — bounded per-peer outbound buffer on
  `OwnerMultiplexer`: buffer while `markPeerOffline`, flush on `markPeerOnline`.
  Mirrors the inbound bounded-queue pattern. Wire/relay/app invariant.
  `depends_on: []`, parent `epic-remote-session-resilience-refactor`.
  Five design questions pre-staged (buffer location, bound+overflow, flush
  ordering vs `session_sync`, teardown, `lateAttach` interaction) for
  feature-design.
- **2b (parked as backlog `idea-outbound-delivery-detection-lag-window`)** —
  the detection-lag window. Needs relay-side hold (conflicts with "relay stays
  opaque," intersects `gate-security-unbounded-outbound-queues`) or app auto-
  `session_sync`-on-reconnect. Wire/component-bearing → its own design pass,
  likely an epic with a `PROTOCOL.md` delivery-guarantee roll-forward.
- **Resolved `idea-extension-pumps-into-dead-app-peer`** (backlog) — its open
  question ("does the extension get a `peer_offline` signal?") answered YES;
  annotated in place. Retained as symptom record; both windows now covered by
  the two child items.

## The debug-env investigation — and a VERDICT the skills-repo story does NOT solve our use case

Operator asked for the export command + config location to enable
`REMOTE_PI_DEBUG_LOG=1` (the pi-extension delivery-path ring/file log at
`~/.pi/remote/debug/delivery.log`). Found it was **off** in the live pi process
(`/proc/*/environ` showed only PATH/TERM/PWD — no `REMOTE_PI_*`), which is why
the delivery log stopped at the `13:04:28 quit` and had no entries from the new
session.

### The export command (for the record)

```bash
export REMOTE_PI_DEBUG_LOG=1
```

But exporting it in a shell is insufficient — it's stripped before pi starts.

### Where the var is read (decisive for the verdict)

`delivery_debug_log.ts:250-251` — `createDeliveryDebugLog()` reads
`process.env["REMOTE_PI_DEBUG_LOG"]` at **module load**, called from
`index.ts:1219` (`let _deliveryDebugLog = createDeliveryDebugLog()`) in the
**pi extension process**. Not in bash subprocesses. So the var must be in
pi's own process env at extension load time.

### Three layers, clarified (I conflated them earlier — corrected here)

1. **Outer PID 1 bwrap** (wraps the whole pi session, `--clearenv` + hardcoded
   `--setenv PATH/HOME/TERM/LANG`). This is what strips `REMOTE_PI_DEBUG_LOG`
   from pi's own env. PID 1's parent is `code-server@agent.service`
   (`systemd → /usr/bin/code-server`). **This is a dev-VM / code-server launch
   config, NOT the pi-sandbox extension.** Its allowlist is NOT configurable
   from either repo.
2. **pi-sandbox extension** (`skills/plugins/pi-sandbox`) — does NOT wrap pi's
   own session. Its header (`sandbox.ts:2-19`) is explicit: "OS-level
   sandboxing for **mediated bash + file tools**… overrides the tool-registry
   `bash`, `read`, `write`, and `edit` tools." `session_start` (line 498)
   "intentionally leaves process.env untouched." No re-exec/relaunch/session-
   wrap. It only governs the env of **bash-tool subprocesses** via
   `createSandboxedBashOps` → `buildMinimalEnv` (hardcoded allowlist:
   PATH/HOME/TERM/LANG/TMPDIR/LC_*).
3. **`bash` tool spawns** — per-command inner bwrap, same `buildMinimalEnv`
   allowlist as layer 2.

### VERDICT: `feature-pi-sandbox-env-add-config` does NOT solve our use case

The skills-repo story (`skills/.work/active/features/feature-pi-sandbox-env-add-config`,
filed 2026-07-09) adds config-driven `envAdd` (`values` + `passthrough`) to
extend the minimal env for **sandboxed bash tool subprocesses** (layer 3), with
`minimal → add → scrub` ordering and global/operator-only trust. It's a
well-scoped, correct feature for its stated goal (operators injecting
`NODE_ENV`/`CI`/`DATABASE_URL` into bash subprocesses).

**But it does not enable the live `REMOTE_PI_DEBUG_LOG` delivery log**, because:
- The delivery log reads `process.env` in the **pi extension process** (layer 1),
  at module load.
- `envAdd` only governs **bash-tool subprocess** env (layer 3).
- The var is stripped by the **outer PID 1 bwrap** (layer 1), which the
  pi-sandbox extension never touches and `envAdd` cannot influence.

The feature's own touch surface confirms this: it lists `sandbox.ts` →
"pass loaded `envAdd` into `createSandboxedBashOps`'s `buildMinimalEnv` call" —
the bash-tool path only. No session-wrap / relaunch path is touched (there is
none to touch).

### What WOULD solve our use case

Add `--setenv REMOTE_PI_DEBUG_LOG 1` (or a pass-through) to the **outer PID 1
bwrap** — wherever the dev-VM / code-server launch constructs that argv. This
is outside both repos (`remote_pi` and `skills`). The exact launcher file was
NOT located this session (see Mistakes below). The pi-sandbox extension cannot
help here because it loads *inside* pi and only mediates tools; it cannot wrap
pi's own launch (chicken-and-egg).

**Adjacent benefit of `envAdd` (not the primary use case):** `passthrough:
["REMOTE_PI_DEBUG_LOG"]` would let us unit-test `delivery_debug_log.ts`
behavior by running `REMOTE_PI_DEBUG_LOG=1 node …` in a bash-tool subprocess.
Useful for testing the module in isolation, but does not enable the live
delivery log in pi.

### Operator's stated plan

Operator will implement the env-var fix in the `skills/` repo. If the intent is
to enable the live delivery log, that fix is in the **wrong layer** — it needs
to land in the dev-VM/code-server outer-bwrap launch config, not the pi-sandbox
extension. If the intent is the general `envAdd` capability for bash
subprocesses (the story's actual scope), it's correct and valuable but
orthogonal to the debug-log need. **Flag this to the operator before they
invest implementation time expecting it to turn on the delivery log.**

## Mistakes / course corrections

- **Hung a tool call on `rg -rln … / ` (filesystem-wide recursive grep).**
  Scanned the entire root including container overlay layers; blocked ~16k
  seconds. Should never run an unbounded filesystem-wide grep. The target
  (the outer-bwrap launcher script) should have been found via bounded reads
  (`systemctl cat`, `ps -o args= -p <code-server-pid>`, code-server config),
  not a root-wide ripgrep. Did not re-attempt; the launcher file remains
  unlocated.
- **Initially conflated the three env layers** and told the operator the
  pi-sandbox extension's `buildMinimalEnv` was "what strips the var from pi."
  Corrected after reading the extension header + session_start comment: the
  extension only mediates tools; the outer PID 1 bwrap is a separate dev-VM
  layer. The correction changed the verdict on the skills-repo story.
- **Early in the session, provider errors interrupted turns** (operator noted
  "provider errors, you'll have to retry"). Re-established context each time
  from logs/code rather than memory.

## Handoff / next

- **`feature-outbound-buffer-on-peer-offline`** is at `stage: drafting` —
  `/agile-workflow:feature-design` picks it up. Load-bearing design question is
  #3 (flush ordering vs `session_sync`): a naive flush on `markPeerOnline`
  would duplicate frames if the app concurrently pulls `session_sync`. Cleanest
  answer is likely "flush only frames newer than the sync high-water mark," but
  that couples this feature to the app's reconnect behavior (which today doesn't
  auto-sync — that's exactly why 2b exists separately). Feature-design should
  make that tradeoff explicit, not pick silently.
- **Debug-env:** before implementing in `skills/`, confirm with operator whether
  the goal is the live delivery log (→ wrong layer; needs outer-bwrap config)
  or the general `envAdd` capability (→ correct, orthogonal). If the live log
  is wanted now, the unblocking move is to locate and edit the dev-VM/code-server
  outer-bwrap launch config (bounded reads only — no root-wide greps).
- **Restarting session** for pi + model upgrades. The scoped feature + parked
  backlog items are committed (bb08d91) and survive the restart. No in-flight
  uncommitted edits.

## References

- Scoped feature: `.work/active/features/feature-outbound-buffer-on-peer-offline.md`
- Parked 2b: `.work/backlog/idea-outbound-delivery-detection-lag-window.md`
- Resolved symptom record: `.work/backlog/idea-extension-pumps-into-dead-app-peer.md`
- Inbound symmetry: `.work/active/features/feature-session-stable-message-delivery.md`
- Delivery log module: `pi-extension/src/session/delivery_debug_log.ts:250`
- Drop site: `pi-extension/src/extension/owner_multiplexer.ts:450`
- Signal consumption: `pi-extension/src/index.ts:331-342`
- Skills-repo story (verified NOT solving debug-env use case):
  `skills/.work/active/features/feature-pi-sandbox-env-add-config.md`
- pi-sandbox extension scope (tool-only, no session wrap):
  `skills/plugins/pi-sandbox/extensions/sandbox.ts:2-19, 498`
