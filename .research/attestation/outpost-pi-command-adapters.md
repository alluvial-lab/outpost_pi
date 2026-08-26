---
source_handle: outpost-pi-command-adapters
fetched: 2026-08-26
source_path: pi-extension/src/extension/command_surface/commands.ts
provenance: source-direct
substrate_confidence: source-direct
---

# Outpost-Pi Pi-SDK command adapter

Paraphrased summary: The command-surface module's current public spec is typed around `ExtensionCommandContext` because it is the Pi `registerCommand` adapter, and it registers separate names such as `outpost-pi setup`. It does not expose an operation dispatcher independent of Pi command registration.

## Key passages

- Lines 10-15 define `OutpostPiCommandSpec.run` with `ExtensionCommandContext`.
- Lines 19-28 register the root `outpost-pi` command.
- Lines 30-35 register each subcommand as a separate Pi command and delegate to the spec's `run` callback.

## Structural metadata

- Source type: current Outpost-Pi TypeScript source
- Architectural role: Pi command-surface adapter
