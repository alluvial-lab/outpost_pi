---
source_handle: outpost-pi-local-mesh-commands
fetched: 2026-08-26
source_path: pi-extension/src/extension/command_surface/local_mesh_commands.ts
provenance: source-direct
substrate_confidence: source-direct
---

# Outpost-Pi local mesh command contexts

Paraphrased summary: Root, setup, peers, stop, and join consume only base `ExtensionContext` UI/cwd subsets. Setup has an additional interactive `ui.select` requirement.

## Key passages

- Lines 39-59 declare dependencies using base UI/cwd subsets.
- Lines 94-176 implement root with base UI/cwd; the first-run path uses a setup wizard.
- Lines 176-191 implement setup with base UI/cwd and explicitly require `ui.select`.
- Lines 208-263 implement peers and stop using UI-only subsets, then join using base UI/cwd.

## Structural metadata

- Source type: current Outpost-Pi TypeScript source
- Relevant class: `LocalMeshCommands`
