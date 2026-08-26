---
source_handle: outpost-pi-pairing-commands
fetched: 2026-08-26
source_path: pi-extension/src/extension/command_surface/pairing_commands.ts
provenance: source-direct
substrate_confidence: source-direct
---

# Outpost-Pi pairing adapter contexts

Paraphrased summary: Pair, devices, and revoke accept only base extension UI/cwd subsets and delegate to `PairingCoordinator`.

## Key passages

- Lines 5-18 define `PairingCommands`; pair/revoke use `Pick<ExtensionContext, "ui" | "cwd">`, and devices uses UI only.

## Structural metadata

- Source type: current Outpost-Pi TypeScript source
- Relevant class: `PairingCommands`
