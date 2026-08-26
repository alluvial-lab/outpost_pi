---
source_handle: outpost-pi-relay-command-handler
fetched: 2026-08-26
source_path: pi-extension/src/extension/command_surface/relay_commands.ts
provenance: source-direct
substrate_confidence: source-direct
---

# Outpost-Pi relay command context

Paraphrased summary: Relay start and relay-URL mutation consume only base extension UI/cwd subsets and local adapters; they do not use command-only SDK session controls.

## Key passages

- Lines 6-11 define relay start with `Pick<ExtensionContext, "ui" | "cwd">`.
- Lines 13-37 implement set-relay with `Pick<ExtensionContext, "ui">`, URL validation, config persistence, and notifications.

## Structural metadata

- Source type: current Outpost-Pi TypeScript source
- Relevant class: `RelayCommands`
