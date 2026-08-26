---
source_handle: pi-sdk-0-80-6-extensions-docs
fetched: 2026-08-26
source_path: pi-extension/node_modules/@earendil-works/pi-coding-agent/docs/extensions.md
provenance: source-direct
substrate_confidence: source-direct
---

# Pi 0.80.6 extension command documentation

Paraphrased summary: The installed extension docs separate command-only session controls from base extension contexts and describe `pi.getCommands()` as discovery for prompt invocation. A reload example suggests extension-side `sendUserMessage()` can queue a command, which conflicts with the installed runtime implementation.

## Key passages

- Lines 1071-1075 say command handlers receive `ExtensionCommandContext`, whose session-control methods are command-only because event-handler use can deadlock.
- Lines 1295-1317 show an extension tool calling `pi.sendUserMessage("/reload-runtime", { deliverAs: "followUp" })`.
- Lines 1518-1544 document `pi.getCommands()` as command discovery for later prompt invocation and exclude built-in interactive commands.

## Structural metadata

- Source type: installed package documentation
- Relevant sections: `ExtensionCommandContext`, reload example, `pi.getCommands()`
