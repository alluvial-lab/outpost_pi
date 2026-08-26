---
source_handle: pi-sdk-0-80-6-extension-types
fetched: 2026-08-26
source_path: pi-extension/node_modules/@earendil-works/pi-coding-agent/dist/core/extensions/types.d.ts
provenance: source-direct
substrate_confidence: source-direct
---

# Pi 0.80.6 extension API and context types

Paraphrased summary: The installed declarations separate base event/tool operations from session-control operations. `ExtensionContext` contains UI, cwd, session/model access, idle/abort/shutdown, and callback-style `compact`. `ExtensionCommandContext` adds wait-for-idle and session replacement/navigation/reload. `ExtensionAPI` can register commands and discover command metadata, but does not expose a direct command-invocation method.

## Key passages

- Lines 211-241 define `ExtensionContext`; `compact(options?)` is a base-context callback-style operation at lines 237-238.
- Lines 243-282 define `ExtensionCommandContext` as extending the base context with `waitForIdle`, `newSession`, `fork`, `navigateTree`, `switchSession`, and `reload`.
- Lines 828-928 define `ExtensionAPI`; command-related methods are `registerCommand` at lines 874-876 and discovery-only `getCommands` at lines 922-923. No `invokeCommand`/`executeCommand` member is declared.
- Lines 895-905 expose `sendMessage` and `sendUserMessage`; neither signature is a direct command-invocation API.
- Lines 1170-1208 define the separate `ExtensionCommandContextActions` binding used to supply command-only operations.

## Structural metadata

- Source type: installed TypeScript declarations
- Relevant symbols: `ExtensionContext`, `ExtensionCommandContext`, `ExtensionAPI`, `ExtensionCommandContextActions`
