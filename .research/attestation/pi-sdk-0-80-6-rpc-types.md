---
source_handle: pi-sdk-0-80-6-rpc-types
fetched: 2026-08-26
source_path: pi-extension/node_modules/@earendil-works/pi-coding-agent/dist/modes/rpc/rpc-types.d.ts
provenance: source-direct
substrate_confidence: source-direct
---

# Pi 0.80.6 RPC command declarations

Paraphrased summary: The public RPC union includes dedicated host/session operations and command discovery, but no named `invoke_command` message. Registered extension commands are described as invokable through `prompt`.

## Key passages

- Lines 15-37 declare `prompt`, `steer`, `follow_up`, `abort`, and dedicated `new_session` RPC commands.
- Lines 38-129 enumerate other dedicated operations including model, thinking, compact, session switch/fork/clone, and `get_commands`; there is no named command-execution variant.
- Lines 131-142 define `RpcSlashCommand` and explicitly describe it as a command available for invocation via prompt.

## Structural metadata

- Source type: installed TypeScript declarations
- Relevant type: `RpcCommand`
