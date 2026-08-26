---
source_handle: pi-sdk-0-80-6-rpc-mode
fetched: 2026-08-26
source_path: pi-extension/node_modules/@earendil-works/pi-coding-agent/dist/modes/rpc/rpc-mode.js
provenance: source-direct
substrate_confidence: source-direct
---

# Pi 0.80.6 RPC mode command reachability

Paraphrased summary: RPC mode binds full extension command-context operations, and its `prompt` command delegates to `AgentSession.prompt()`. Therefore an external RPC client can invoke a registered extension command by sending a prompt whose message is the slash command.

## Key passages

- Lines 227-258 rebind the active RPC session and supply `commandContextActions` for wait-for-idle, new session, fork, tree navigation, session switch, and reload.
- Lines 297-317 handle an RPC `prompt` by calling `session.prompt(command.message, ...)`, forwarding RPC source and streaming behavior.
- Lines 323-330 expose a separate dedicated RPC `new_session` operation.
- Lines 508-526 implement `get_commands` as discovery of extension commands, prompt templates, and skills; it returns metadata rather than directly executing a named command.

## Structural metadata

- Source type: installed compiled RPC runtime
- Mode: `pi --mode rpc`
