---
source_handle: outpost-pi-cron-command-handler
fetched: 2026-08-26
source_path: pi-extension/src/extension/command_surface/cron_commands.ts
provenance: source-direct
substrate_confidence: source-direct
---

# Outpost-Pi cron command context

Paraphrased summary: The cron dispatcher and all subcommands accept the base extension UI capability and call the supervisor; no command-only SDK session-control method is used.

## Key passages

- Lines 16-46 dispatch cron subcommands using `UiCtx`.
- Lines 49-140 implement add/list/remove/enable/disable/run/log with `Pick<ExtensionContext, "ui">` and supervisor requests.

## Structural metadata

- Source type: current Outpost-Pi TypeScript source
- Relevant class: `CronCommands`
