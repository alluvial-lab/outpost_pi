---
source_handle: pi-sdk-0-80-6-changelog
fetched: 2026-08-26
source_path: pi-extension/node_modules/@earendil-works/pi-coding-agent/CHANGELOG.md
provenance: source-direct
substrate_confidence: source-direct
---

# Pi SDK command-surface history visible in 0.80.6

Paraphrased summary: The installed changelog shows that headless command discovery and extension command discovery were added in 0.50.2/0.51.3, session replacement moved from `AgentSession` to `AgentSessionRuntime` in 0.65.0, stale-context/withSession semantics hardened in 0.69.0, and external prompt-based extension command execution has supported streaming-aware RPC prompt dispatch since 0.32.2.

## Key passages

- Lines 2628-2642: version 0.50.2 added RPC `get_commands` for headless discovery.
- Lines 2422-2436: version 0.51.3 added `ExtensionAPI.getCommands()` for commands "for invocation via `prompt`".
- Lines 1419-1500: version 0.65.0 introduced `AgentSessionRuntime` and removed session replacement methods from `AgentSession`.
- Lines 1075-1101: version 0.69.0 made stale pre-replacement extension objects throw and added fresh `withSession` replacement callbacks.
- Lines 3624-3636: version 0.32.2 documented immediate extension-command execution and added streaming behavior to SDK/RPC prompt dispatch.

## Structural metadata

- Source type: installed package changelog
- Scope: command discovery/invocation and session replacement changes relevant to the current 0.80.6 surface
