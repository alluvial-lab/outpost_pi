---
source_handle: outpost-pi-daemon-command-handler
fetched: 2026-08-26
source_path: pi-extension/src/extension/command_surface/daemon_commands.ts
provenance: source-direct
substrate_confidence: source-direct
---

# Outpost-Pi daemon command contexts

Paraphrased summary: Every daemon registry/fleet operation accepts `UiCtx`, defined as the base extension UI capability; no command-only SDK session-control method is used.

## Key passages

- Line 7 defines `UiCtx = Pick<ExtensionContext, "ui">`.
- Lines 25-232 implement create, remove, list, status, start, stop, restart, and send entirely through UI notifications plus registry/supervisor adapters.

## Structural metadata

- Source type: current Outpost-Pi TypeScript source
- Relevant class: `DaemonCommands`
