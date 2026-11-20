---
id: idea-agy-push-turn-delivery
created: 2026-11-19
updated: 2026-11-20
tags: [pi-extension, research]
---

# Antigravity (agy) push-turn delivery via sidecar UDS relay (Slice 2)

Follow-up to MCP push-turn delivery (Part 2b empirical probe on `agy` 1.5.12, Linux). Full probe record and architecture details live in [agy-push-delivery.md](../../pi-extension/docs/agy-push-delivery.md).

## Settled empirical findings (clean-environment probes)

- `~/.gemini/antigravity-cli/bin/agentapi` (`exec "/usr/local/bin/agy" agentapi "$@"`) exposes `send-message [--title=<title>] <recipient_id> <content>` (supporting self-delivery for async notifications), and requires `ANTIGRAVITY_LS_ADDRESS` + `ANTIGRAVITY_CSRF_TOKEN` in its environment (without them it immediately returns `{"error": "ANTIGRAVITY_LS_ADDRESS is not set"}`).
- **Stdio MCP subprocesses (`mesh_server.js`)** inherit **zero `ANTIGRAVITY_*` env vars** (`ANTIGRAVITY_LS_ADDRESS`, `ANTIGRAVITY_CSRF_TOKEN`, and `ANTIGRAVITY_CONVERSATION_ID` are all absent). A direct MCP-only `agentapi` adapter cannot work standalone.
- **`SessionStart` hooks (`hooks.json`)** receive `ANTIGRAVITY_CONVERSATION_ID` (and stdin JSON `{ conversationId, cwd, workspacePaths }`) **but also lack `ANTIGRAVITY_LS_ADDRESS` and `ANTIGRAVITY_CSRF_TOKEN`** — eliminating the `SessionStart` credential-passing fallback.
- **`agy` CLI has no sidecar manager:** `agy --help` exposes no sidecar subcommands, no sidecars run on CLI installs, and global `sidecar.json` automation requires opt-in through the Antigravity 2.0 Desktop Automations dashboard (`sidecar://dashboard`).

## Recommended Slice 2 split (by Antigravity surface)

- **Antigravity 2.0 Desktop (sidecars available):** Ship an opt-in sidecar (`sidecar.json`, `restart_policy: "on-failure"`) holding runtime-injected `ANTIGRAVITY_LS_ADDRESS` / `ANTIGRAVITY_CSRF_TOKEN` strictly in memory behind an owner-only (`0700`/`0600`) UDS, paired with a `SessionStart` hook writing an atomic `0600` `(cwd → conversationId)` binding (never persisting `ANTIGRAVITY_CSRF_TOKEN`). `mesh_server.js` remains the sole `MeshNode` peer and plugs an `AgySidecarPushTransport` into `PushDeliveryTransport` / `createPushDeliveryCoordinator` (reusing the 5s `WakeGate`, 64 KiB `PUSH_BATCH_MAX_BYTES` cap below Linux `MAX_ARG_STRLEN`, local-only `isLocalPeerAddress` boundary, `execFile(..., { shell: false })`, and rollback-to-`get_messages` on any failure).
- **Antigravity CLI (`agy`) interactive TUI:** Keep on **inbox-drained** (`get_messages`) mode; optionally add a `Stop` hook that checks an unread-local marker and returns `{ "decision": "continue" }` to flush mid-turn arrivals (cannot wake an already-idle session).
- **Antigravity CLI (`agy`) headless / daemon:** Drive `agy --input-format stream-json --output-format stream-json` (or `agy acp`) under a dedicated wrapper (analogous to `pi-supervisord` RPC) that injects mesh batches directly into stdin.
