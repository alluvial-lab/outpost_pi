---
source_handle: outpost-pi-service-command-handler
fetched: 2026-08-26
source_path: pi-extension/src/extension/command_surface/service_commands.ts
provenance: source-direct
substrate_confidence: source-direct
---

# Outpost-Pi service command context

Paraphrased summary: Service installation and removal use only `UiCtx` for reporting around host service/CLI installation adapters; they do not use command-only SDK session controls.

## Key passages

- Lines 4-42 implement service installation with `UiCtx` and host install/link adapters.
- Lines 44-65 implement uninstall with `UiCtx` and host uninstall/unlink adapters.

## Structural metadata

- Source type: current Outpost-Pi TypeScript source
- Relevant class: `ServiceCommands`
