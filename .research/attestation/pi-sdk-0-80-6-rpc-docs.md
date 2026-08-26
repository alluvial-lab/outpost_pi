---
source_handle: pi-sdk-0-80-6-rpc-docs
fetched: 2026-08-26
source_path: pi-extension/node_modules/@earendil-works/pi-coding-agent/docs/rpc.md
provenance: source-direct
substrate_confidence: source-direct
---

# Pi 0.80.6 RPC command documentation

Paraphrased summary: The installed RPC docs say RPC `prompt` executes extension commands, while queued `steer`/`follow_up` reject them, and `get_commands` discovers invokable extension/template/skill commands.

## Key passages

- Line 67 says an extension command sent as an RPC prompt executes immediately, even during streaming.
- Lines 82-104 say queued `steer`/`follow_up` reject extension commands and callers must use `prompt`.
- Lines 761-795 document `get_commands` and say returned extension/template/skill commands are invoked through `prompt`; built-in TUI commands are excluded.

## Structural metadata

- Source type: installed package documentation
- Relevant sections: `prompt`, `steer`, `follow_up`, `get_commands`
