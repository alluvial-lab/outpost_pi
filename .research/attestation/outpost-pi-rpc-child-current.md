---
source_handle: outpost-pi-rpc-child-current
fetched: 2026-08-26
source_path: pi-extension/src/daemon/rpc_child.ts
provenance: source-direct
substrate_confidence: source-direct
---

# Outpost-Pi current daemon RPC child reachability

Paraphrased summary: The supervisor child wrapper can send Pi RPC `prompt` frames, so it can technically reach prompt-based extension command dispatch. It does not currently provide correlated command results or route extension UI requests back to the mobile owner channel.

## Key passages

- Lines 9-23 describe the wrapper: it spawns `pi --mode rpc`, sends prompt commands, and currently consumes/ignores child stdout beyond limited needs.
- Lines 314-330 implement `sendPrompt` as a fire-and-forget RPC prompt JSONL write and explicitly do not await the response.
- Lines 353-378 parse stdout only for busy transitions and correlated `get_state`, then emit the raw line as an event.
- Lines 381-402 implement the only current request/response pending map, specifically for `get_state` busy checks.

## Structural metadata

- Source type: current Outpost-Pi TypeScript source
- Architectural role: supervisor-owned Pi RPC subprocess adapter
