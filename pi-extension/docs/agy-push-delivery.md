# Antigravity (`agy`) Push-Turn Delivery Evaluation

Design and empirical probe record for delivering Outpost-Pi mesh envelopes directly into Antigravity (`agy`) sessions via `PushDeliveryTransport` ([push_delivery.ts](../src/mcp/push_delivery.ts)), evaluated against the `antigravity-cli` (`agy` 1.5.12) runtime on Linux.

## Summary & Recommendation

- **Direct `agentapi` calls from `mesh_server.js` are not viable in `agy`:** clean-environment probing proves `agy` strips/omits all `ANTIGRAVITY_*` transport variables when spawning stdio MCP subprocesses.
- **`SessionStart` hook credential passing is also not viable in `agy`:** clean-environment probing proves `SessionStart` hooks receive `ANTIGRAVITY_CONVERSATION_ID` (and stdin JSON `{ conversationId, cwd, workspacePaths }`) but do **not** receive `ANTIGRAVITY_LS_ADDRESS` or `ANTIGRAVITY_CSRF_TOKEN`.
- **Antigravity 2.0 Desktop (sidecars available):** implement a **Sidecar UDS Relay** adapter (`PushDeliveryTransport` → owner-only UDS → Antigravity sidecar executing `agentapi send-message`), paired with a `SessionStart` hook registering `(cwd → conversationId)` over the UDS or an atomic `0600` binding file (never persisting `ANTIGRAVITY_CSRF_TOKEN`). Keep `mesh_server.js` as the sole `MeshNode` peer and `(cwd, name)` lock holder.
- **Antigravity CLI (`agy` terminal / headless):** keep interactive TUI sessions on **inbox-drained** (`get_messages`) mode (optionally paired with a `Stop` hook that checks for undrained mid-turn local messages via `decision: "continue"`), because `agy` CLI exposes no sidecar manager and passes no Language Server credentials to MCP servers or `SessionStart` hooks. For unattended headless `agy` daemons, a wrapper driving `agy --input-format stream-json --output-format stream-json` (or `agy acp`) is the sanctioned turn-injection surface.

## Empirical Probe Findings

Probed with `ANTIGRAVITY_*` variables explicitly stripped from the parent environment before invoking `agy` (preventing false positives from an enclosing `agy` shell):

| Surface | `ANTIGRAVITY_LS_ADDRESS` | `ANTIGRAVITY_CSRF_TOKEN` | `ANTIGRAVITY_CONVERSATION_ID` | `agentapi get-conversation-metadata` |
| --- | --- | --- | --- | --- |
| In-turn `run_command` shell (unsandboxed) | Present | Present | Present | **Succeeds** (returns `conversationMetadata` JSON) |
| Stdio MCP subprocess (`mcp_config.json`) | Absent | Absent | Absent | **Fails** (no LS address/token) |
| `SessionStart` hook (`hooks.json`) | Absent | Absent | Present (env + stdin JSON `conversationId`, `cwd`, `workspacePaths`) | **Fails** (no LS address/token) |
| Sidecar (`sidecar.json`, Antigravity 2.0) | Injected by runtime (documented) | Injected by runtime (documented) | Resolved via `SessionStart` binding | **Documented supported surface** |

Additional CLI findings:

- `~/.gemini/antigravity-cli/bin/agentapi` is a thin wrapper (`exec "/usr/local/bin/agy" agentapi "$@"`) exposing `get-conversation-metadata <id>`, `new-conversation`, and `send-message [--title=<title>] <recipient_id> <content>`.
- `agy --help` exposes no `sidecar` / `sidecars` / `automation` subcommand (`acp`, `agent`, `agents`, `changelog`, `help`, `install`, `mcp`, `mic-serve`, `models`, `plugin`, `plugins`, `remote-control`, `update`).
- Built-in automation docs confirm global sidecars (`~/.gemini/config/sidecars/<id>/sidecar.json`) start disabled by default and require user opt-in through the Antigravity 2.0 desktop Automations dashboard (`sidecar://dashboard` / `user_config.json`), which is absent on CLI-only installs.
- `hooks.json` supports `SessionStart`, `PreToolUse`, `PostToolUse`, `PreInvocation`, `PostInvocation`, and `Stop` — there is no `SessionEnd` hook, so conversation bindings can go stale when a session closes.

## Recommended Slice 2 Architecture

### 1. Antigravity 2.0 Desktop — Sidecar UDS Relay + `SessionStart` Binding

1. **Single mesh identity:** `mesh_server.js` remains the sole `MeshNode` participant, owning the `(cwd, name)` lock, `list_peers`, `agent_send`, `get_messages`, and `createPushDeliveryCoordinator` ([push_delivery.ts](../src/mcp/push_delivery.ts)).
2. **`SessionStart` binding hook:** reads `{ conversationId, cwd }` from stdin, validates `conversationId` as a UUID, canonicalizes `cwd` via `realpath`, and atomically writes an owner-only (`0600`) binding file under `~/.pi/remote/agy-sessions/<sha256(canonCwd)>.json` (scoped by optional `OUTPOST_PI_MCP_NAME` when cohabiting). Never persists `ANTIGRAVITY_CSRF_TOKEN`.
3. **Sidecar relay (`sidecar.json`):** runs inside Antigravity's managed sidecar runtime (where `agentapi`, `ANTIGRAVITY_LS_ADDRESS`, and `ANTIGRAVITY_CSRF_TOKEN` are officially provisioned strictly in memory), listens on an owner-only (`0600`) UDS (`~/.pi/remote/agy-push.sock`), validates incoming JSON `{ conversationId, title, content }`, and invokes `execFile("agentapi", ["send-message", "--title", title, conversationId, content], { shell: false, timeout: 5_000 })`.
4. **`PushDeliveryTransport` adapter in `mesh_server.js`:** opted in explicitly (e.g., `--push-deliver=agy`), sends rendered batches over the UDS to the sidecar, and resolves only on zero-exit / error-free JSON output (rejecting otherwise).

### 2. Antigravity CLI (`agy`) — Sanctioned Alternatives

- **Interactive CLI:** stay in **inbox-drained** mode (`get_messages` at turn start). An optional `Stop` hook can inspect an unread-local marker and return `{ "decision": "continue" }` to flush messages that arrived mid-turn (cannot wake an already-idle session).
- **Headless / daemon CLI:** launch `agy --input-format stream-json --output-format stream-json` (or `agy acp`) under a dedicated wrapper (analogous to `pi-supervisord` RPC) that injects mesh batches directly into stdin.

## Rejected Alternatives

- **Direct `agentapi` invocation from `mesh_server.js`:** fails in clean `agy` sessions because MCP subprocesses receive no `ANTIGRAVITY_LS_ADDRESS` or `ANTIGRAVITY_CSRF_TOKEN`.
- **`SessionStart` hook passing LS credentials to a push helper:** eliminated by clean-environment probing showing `SessionStart` hooks also omit `ANTIGRAVITY_LS_ADDRESS` and `ANTIGRAVITY_CSRF_TOKEN`.
- **Sidecar joining the mesh broker directly:** collides with `mesh_server.js` on the `(cwd, name)` lock or splits peer addressing so `agent_send` targets the wrong endpoint.
- **Scraping LS ports/CSRF tokens from `/proc` or `run_command` shells:** violates sandbox/security boundaries and depends on undocumented internal credentials.

## Security & Fallback Invariants

- **Local-only initiative:** reuse `isLocalPeerAddress` ([wake.ts](../src/mcp/wake.ts)); cross-PC (`<pc>:`) and `_relay` envelopes stay in `get_messages` and never invoke `agentapi`.
- **Rate-limiting & batching:** reuse `WakeGate` (`WAKE_MIN_INTERVAL_MS = 5_000`) and `PUSH_BATCH_MAX_BYTES` (`64 KiB`, safely below Linux `MAX_ARG_STRLEN`) via `createPushDeliveryCoordinator` ([push_delivery.ts](../src/mcp/push_delivery.ts)) to bound turn storms and batch sizes.
- **No shell interpolation:** validate `conversationId` against `UUID_RE` and invoke `agentapi` strictly with `execFile(..., { shell: false })`.
- **Zero silent loss:** on any UDS error, timeout, non-zero exit, or JSON `error` field from `agentapi`, reject from `PushDeliveryTransport.deliver` so `createPushDeliveryCoordinator` rolls the batch and drop count back into `inbox` (`get_messages`), and invalidate stale `conversationId` bindings on permanent not-found errors.

## Revisit Conditions

- Antigravity adds an official MCP channel / push notification capability or provisions `agentapi` credentials to opted-in MCP servers (re-enables a direct `PushDeliveryTransport` adapter without a sidecar).
- `agy` CLI adds native sidecar lifecycle management (unifies CLI and Desktop onto the Sidecar UDS Relay).
