---
name: pi-extension-typescript
description: Remote Pi pi-extension TypeScript/Pi SDK reference. Read before editing or reviewing pi-extension/ code, session lifecycle hooks, relay/room metadata, mesh tools, pairing, or Pi SDK integration.
updated: 2026-08-16
---

# Pi Extension TypeScript Reference

> Local scope: `pi-extension/`
> Versions: Node >=20, TypeScript `^7.0.2`, `@earendil-works/pi-coding-agent` 0.80.x, `ws` 8.x, Vitest 4.x
> Canonical local docs: `pi-extension/CLAUDE.md`, `PROTOCOL.md`, Pi docs at `/home/agent/.local/lib/node_modules/@earendil-works/pi-coding-agent/docs/extensions.md` [pi-docs-extensions]{1}
> Source basis: `pi-extension/package.json`, `src/index.ts`, `src/actions/handlers.ts`, `src/transport/relay_client.ts`, `src/pairing/storage.ts`, `src/protocol/{types,codec}.ts`, `src/session/*`, and matching tests. [remote-pi-package-config]{1} [remote-pi-index-lifecycle]{1}

## When to load

- Any edit or review under `pi-extension/`.
- Any change involving `/outpost-pi`, session replacement (`/new`, `/resume`, `/fork`, `/reload`), mobile/client state, `room_meta`, mesh tools, pairing, relay connection, or broker/UDS behavior.
- Any investigation of stale context, stuck `Working`, dropped/replayed events, or multi-client state.

## Package commands

Run from `pi-extension/`; these commands are declared in `package.json`. [remote-pi-package-config]{1}

```bash
corepack pnpm install   # if deps are missing
corepack pnpm typecheck # tsc --noEmit
corepack pnpm test      # vitest run
corepack pnpm build     # tsc -> dist/
```

### Sandbox toolchain (dev VM / `dev-vm`)

`/home/agent/.cache` is mounted **read-only** on this sandbox, so pnpm 11.x
fails with `[ERR_SQLITE_ERROR] unable to open database file` unless the store
and caches are redirected off it. `/home/agent/.npmrc` is a broken char device
(a harmless `EACCES` warning is emitted — ignore it). Always prefix pnpm with
repo-local env:

```bash
cd pi-extension
export PNPM_HOME=~/projects/outpost_pi/.pnpm-store
export npm_config_cache=~/projects/outpost_pi/.npm-cache
export XDG_CACHE_HOME=~/projects/outpost_pi/.xdg-cache
# if node_modules is missing, install once with the explicit store-dir:
corepack pnpm install --store-dir ~/projects/outpost_pi/.pnpm-store
corepack pnpm typecheck
corepack pnpm exec vitest run <path/to/test.ts>   # targeted; full `pnpm test` has known env UDS/cwd-lock failures (EPERM on /tmp/claude/*.sock)
```

`node_modules/` and the `.pnpm-store`/`.npm-cache`/`.xdg-cache` dirs are
gitignored local state; do not commit them.

Do not commit `dist/`, `node_modules/`, local `.pi/`, secrets, or generated build output.

## Module and TypeScript conventions

```ts
// ESM + NodeNext: relative imports include .js in TypeScript source.
import { RelayClient } from "./transport/relay_client.js";
import type { ClientMessage } from "./protocol/types.js";

// Prefer unknown + narrowing at boundaries.
function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}
```

- ESM only (`"type": "module"`); no `require`, `module.exports`, or CommonJS-only dependencies.
- Strict TypeScript; avoid `any` except at explicitly isolated test seams.
- Top-level await is allowed by ESM, but long-lived runtime work should be owned by lifecycle handlers and tear down on `session_shutdown`.
- Use named `Error` classes at boundaries; throw early when input/config is invalid.

## Pi SDK lifecycle quick reference

Pi extension lifecycle facts are load-bearing for Remote Pi and should be checked against the installed Pi extension docs when Pi SDK versions change. [pi-docs-extensions]{1}

```ts
pi.on("session_start", async (event, ctx) => {
  // reason: "startup" | "reload" | "new" | "resume" | "fork"
  // Re-establish session-scoped in-memory state here.
});

pi.on("session_shutdown", async (event, ctx) => {
  // reason: "quit" | "reload" | "new" | "resume" | "fork"
  // Tear down relay, mesh, sockets, timers, and stale ctx refs here.
});

pi.on("turn_start", async (event, ctx) => {
  // event.turnIndex, event.timestamp
});

pi.on("turn_end", async (event, ctx) => {
  // event.turnIndex, event.message, event.toolResults
});
```

Hooks actually used across the extension include: [remote-pi-index-lifecycle]{1}

- `input` — mirrors terminal/RPC input; `CTRL_PREFIX` control messages are swallowed before they become LLM turns.
- `model_select` / `thinking_level_select` — cache current model/thinking and publish `room_meta_update`.
- `message_update`, `tool_execution_start`, `tool_execution_end` — stream assistant/tool telemetry to attached owners.
- `message_end` — records current user and assistant-text facts as durable `outpost-pi.transcript-event.v1` custom entries before broadcasting their transcript projections; execution hooks remain the sole tool transcript producers.
- `agent_end` — finalizes `agent_done`.
- `turn_start` / `turn_end` — publish `room_meta.working`.
- `session_before_compact` / `session_compact` — bracket compact working-state and record the durable `compaction_recorded` transcript entry before live visibility.
- `session_start` / `session_shutdown` — capture the freshest session-bound context and tear down stale outgoing instance. These are registered in `pi-extension/src/extension/composition_root.ts` via `registerLifecycleHooks(pi, ports, ...)`, not directly in `src/index.ts`; `index.ts` is the composition entrypoint that wires the `OutpostPiRuntimePorts` seam and invokes `registerLifecycleHooks`.
- `session_shutdown` — tear down stale outgoing instance.

Session action helpers use `ctx.compact()`, `ctx.newSession({ withSession })`, `ctx.getModel()`, `ctx.abort()`, `pi.setModel(model)`, `pi.setThinkingLevel(level)`, and `SettingsManager.create(cwd)`. `ctx.getModel()` is used defensively in source even though it is less prominently documented than core lifecycle hooks; verify SDK types before changing that call path. [remote-pi-index-lifecycle]{1}

Session replacement order from Pi docs:

```text
/new or /resume
  -> session_before_switch
  -> session_shutdown       # old extension instance/context
  -> session_start          # new session context
  -> resources_discover
```

`/fork` and `/clone` similarly emit `session_shutdown` then `session_start` with `reason: "fork"`. Treat all captured command/event contexts as session-scoped, not process-global.

## Remote Pi state boundaries

Important files:

- `src/index.ts` — extension factory and composition entrypoint; wires runtime ports, relay/room metadata, lifecycle hooks, and command adapters.
- `src/extension/command_surface/commands.ts` — registers the `/outpost-pi` root command and injected subcommands with the Pi SDK.
- `src/protocol/types.ts` — narrow re-export of schema-generated app/extension message unions. [remote-pi-protocol-types]{1}
- `src/protocol/codec.ts` — app↔Pi inner-message JSON decoder backed by generated type registries and runtime predicates. `src/protocol/relay_ingress.ts` is the live relay boundary: it caps raw/base64 work, then consumes generated outer/control/cross-PC predicates before decode-once typed fanout. The generated outer contract exposes a strict room-required predicate plus a `compat` predicate that relaxes only room presence; both reject empty declared strings and unknown properties. [remote-pi-protocol-codec]{1}
- `src/actions/handlers.ts` — typed mobile/app actions (`session_new`, `session_compact`, `model_set`, `thinking_set`, `list_models`).
- `src/transport/relay_client.ts`, `src/transport/peer_channel.ts`, `src/transport/pi_forward_client.ts` — relay WebSocket, per-peer channels, and cross-PC Pi envelope forwarding.
- `src/session/*` — local UDS broker, mesh node, peer inventory, tools, cwd lock, leader election, broker remote bridge.
- `src/pairing/*` — QR/session token, key storage, peer records.
- `src/ui/footer.ts` — TUI footer rendering.
- High-value tests: `src/extension.test.ts`, `src/actions/handlers.test.ts`, `src/transport/relay_client.test.ts`, `src/pairing/storage.test.ts`, `src/config.test.ts`, `src/protocol/codec.test.ts`, `src/session/broker_remote.test.ts`.

State ownership rules:

- The relay routes mobile/app traffic and room control messages; it is not an authority for Pi session internals. [remote-pi-relay-client]{1}
- `room_meta` is the mobile app's hydration surface for room name, cwd, model, thinking, and `working` state. [remote-pi-index-lifecycle]{1}
- `_lastEventCtx`/current session context is the safe route for session actions after replacement; old command contexts can become stale. [remote-pi-index-lifecycle]{1}
- Mesh peers are agent endpoints (`<cwd>@<name>`), not human devices or UI clients. Cross-PC routing prefixes are broker/relay concerns, not human-client presence signals. [remote-pi-broker-remote]{1}

## Lifecycle gotchas

### Stale context after session replacement

Recent bug class: callbacks captured an old Pi `ctx` and later used it after `/new`, `/resume`, reload, or reconnect. Pi marks old contexts stale; touching stale `ctx.ui`, `ctx.abort`, or similar can throw and crash or strand callbacks.

Rules:

- Re-capture fresh session context on every `session_start`.
- For `ctx.newSession()`, re-capture through the `withSession` callback; the invoking context becomes stale after replacement.
- Prefer `_lastEventCtx` (fresh `session_start` context) for `compact`/`abort`; `_lastCtx` is only a defensive fallback.
- Clear or guard captured contexts on `session_shutdown`.
- Set `_disposed` before awaits in shutdown and re-check `_disposed` after async connect/join/start work to avoid ghost relay/mesh instances.
- Wrap UI/notify/footer paths so stale UI becomes a no-op, not a crash.
- Never route mobile-triggered actions through a command context captured before session replacement when a fresh event context is available.

### `working`/idle convergence

`room_meta.working` should be authoritative and convergent:

- publish `working: true` on `turn_start` and compaction-start paths;
- publish `working: false` on `turn_end`, compaction completion, abort/error cleanup, and session teardown/reconnect hydration where applicable;
- remember that `compact()` does not run a normal turn, so compaction needs manual `working` brackets;
- remember that `session_compact` does not flow through `message_end`; record a durable `compaction_recorded` v1 transcript entry so `session_sync` and process reopen replay the same marker;
- in daemon/RPC mode, `session_new` can acknowledge, reset the mirror, and exit with `EXIT_DAEMON_FRESH_SESSION` (`42`) so the supervisor respawns a fresh Pi session; do not accidentally turn this into an in-process session switch without preserving the daemon contract; [remote-pi-index-lifecycle]{1} [remote-pi-rpc-child]{1}
- cache the latest room meta so reconnect hello carries current state;
- test dropped/replayed update scenarios and app hydration behavior before assuming the UI will self-correct.

The app may debounce or render transitions, but the extension must not leave durable room metadata stuck true after the agent is idle.

### Multi-client and mesh semantics

- Multiple mobile owners can attach to one Pi room; each owner has its own peer channel.
- Local/cross-PC mesh peers are coding-agent endpoints surfaced by agent-network tools.
- Do not infer human workstation/mobile presence from `list_peers`; it returns agent peers only.
- Cross-PC addresses include a `<pc>:` prefix and must be treated as opaque routing keys.

## WebSocket / relay client notes

- Use `ws` only in the extension; `RelayClient` opens with `new WebSocket(toWebSocketUrl(relayUrl))`.
- Persist canonical relay URLs as HTTP(S); convert configured HTTP(S) relay URLs to WS(S) only at transport open.
- Relay URL precedence: `OUTPOST_PI_RELAY` env, then `~/.pi/remote/config.json`; otherwise `resolveRelayUrl()` returns its explicit unconfigured state. I/O boundaries must surface `/outpost-pi set-relay <url>` before URL conversion or socket creation.
- Validate user-facing relay URLs; reject empty/malformed `ws://`/`wss://` in slash command input if the command expects HTTP(S).
- Relay auth flow is `hello { pubkey, room_id?, room_meta? }` → `challenge { nonce }` → `auth { sig }`. [remote-pi-relay-client]{1}
- Liveness watchdog closes after roughly 70 seconds of no inbound activity; relay pings are expected to keep it alive. [remote-pi-relay-client]{1}
- `sendControl()` is best-effort/no-op when closed; do not assume a closed relay saw an update. [remote-pi-relay-client]{1}
- `PiForwardClient` multiplexes `pi_envelope` / `pi_envelope_in` over the relay WebSocket for cross-PC mesh forwarding. [remote-pi-broker-remote]{1}
- Reconnect code must rehydrate room metadata and bridge state without creating phantom rooms or ghost brokers.

## Pairing, protocol, and key storage notes

- Pairing storage uses `@napi-rs/keyring` when available: service `dev.outpostpi.pi`, account `longterm-ed25519`. [remote-pi-pairing-storage]{1}
- Headless Linux/no secret-service fallback is `~/.pi/remote/identity.json` with file mode `0600` and directory mode `0700`. [remote-pi-pairing-storage]{1}
- Transient keyring failures should retry rather than generating a new identity. [remote-pi-pairing-storage]{1}
- Peer records live in `~/.pi/remote/peers.json`; relay config in `~/.pi/remote/config.json`; local per-cwd config in `<cwd>/.pi/remote-pi/config.json`. [remote-pi-pairing-storage]{1}
- Do not hand-roll crypto. Use existing helpers in `src/pairing/crypto.ts` and protocol helpers.
- Peer records and owner keys are machine/global state; update caches after add/remove and avoid stale in-memory assumptions.
- `OUTPOST_PI_PAIR_CODE_FILE` is the headless pairing-code retrieval seam used by Cockpit and the E2E harness. When set, `/outpost-pi pair` atomically publishes the production-generated `{uri, token, expiresAt, roomId, name}` JSON through a same-directory owner-only (`0600`) temporary file, rejects pre-existing or symlink targets, and never logs or routes the bearer token through `sendMessage`/model context. The consumer owns deletion after use.

Protocol families to recognize:

- Client/app messages: `pair_request`, `user_message` (`images?`, `streaming_behavior?`), `queued_message_set`, `queued_message_clear`, `approve_tool`, `cancel`, `ping`, `session_sync`, `session_new`, `session_compact`, `model_set`, `thinking_set`, `list_models`, and the capture-upload control sequence `capture_upload_begin`, `capture_upload_chunk`, `capture_upload_end`. `approve_tool` is present in the type union but currently forward-compatible/ignored by the router. Capture uploads are schema-owned and bounded by the generated limits: 8 KiB decoded per chunk (10,924 base64 characters), 2 MiB total, and one in-flight upload per session; `src/actions/capture_upload_handler.ts` consumes the generated union and `src/index.ts` dispatches the family. [remote-pi-protocol-types]{1} [remote-pi-index-lifecycle]{1}
- Server/extension messages: `pair_ok`, `pair_error`, `user_input`, `user_message`, `queued_message_state`, `agent_chunk`, `agent_done`, `agent_message`, `compaction`, `tool_request`, `tool_result`, `error`, `cancelled`, `pong`, `bye`, `session_history`, `action_ok`, `action_error`, `models_list`, and the capture-upload replies `capture_upload_ack` / `capture_upload_error`. [remote-pi-protocol-types]{1}

## Anti-patterns

- Holding a module-level `ctx`/`ctx.ui` forever and using it after `/new`, `/resume`, or reload.
- Reusing `_lastCtx` after `newSession` when `_lastEventCtx` or `withSession` is available.
- Using `message_end` as a compaction signal; compaction has its own hooks and must cross the durable v1 transcript boundary before live visibility.
- Treating relay connection success as proof of current room/session state without sending fresh room meta.
- Publishing `working: true` without guaranteed false paths for turn end, errors, aborts, compaction, and shutdown.
- Persisting `ws://` or `wss://` as user config when the canonical user-facing relay setting is HTTP(S).
- Regenerating identity just because macOS/Windows keyring is temporarily locked or unavailable.
- Logging payload contents or secrets while debugging relay/peer traffic.
- Composing peer addresses by hand; use broker-issued addresses verbatim.
- Adding source-local relay frame guards or DTO mirrors; `relay_ingress.ts` must consume the schema-generated outer/control/cross-PC predicates, and outbound adapters must use generated wire types. [remote-pi-protocol-codec]{1}
- Mutating `_activePeers` or mesh/broker internals outside the helper paths that refresh footer/log/state.
- Adding broad dependencies without checking ESM compatibility and test impact.

## Review checklist

Before approving `pi-extension/` changes:

- [ ] Does every opened socket/timer/relay/mesh resource tear down on `session_shutdown`?
- [ ] Does every async start/connect/join path re-check `_disposed` before publishing state?
- [ ] Are session-replacement paths re-capturing context through `withSession` or `session_start`?
- [ ] Does reconnect send an authoritative room snapshot, not just event deltas?
- [ ] Can `working` converge false after success, error, abort, compaction, and reconnect?
- [ ] Is `session_sync` still consistent after stop/start/reconnect, including compaction markers?
- [ ] Are relay URLs canonicalized and validated at the boundary?
- [ ] Does key storage preserve existing pairing across locked keyrings and headless fallback?
- [ ] Are multi-owner, mesh-peer, and human-client semantics kept separate?
- [ ] Are cross-PC envelopes using verified `from_pc` and prefix anti-spoof checks in `BrokerRemote.handleIncoming`? [remote-pi-broker-remote]{1}
- [ ] Do tests cover stale ctx, compaction marker replay, relay liveness, keyring fallback, and the lifecycle/protocol edge touched by the change?
- [ ] Did `corepack pnpm typecheck`, `corepack pnpm test`, and `corepack pnpm build` pass?
