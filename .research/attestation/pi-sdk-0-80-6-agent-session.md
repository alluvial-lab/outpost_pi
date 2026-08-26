---
source_handle: pi-sdk-0-80-6-agent-session
fetched: 2026-08-26
source_path: pi-extension/node_modules/@earendil-works/pi-coding-agent/dist/core/agent-session.js
provenance: source-direct
substrate_confidence: source-direct
---

# Pi 0.80.6 AgentSession command dispatch

Paraphrased summary: `AgentSession.prompt()` is the installed SDK's general extension-command invocation path. For slash-prefixed input it resolves a registered extension command, creates a command-capable context, and awaits its handler before any normal input/LLM path. In contrast, extension-side `sendUserMessage()` deliberately disables command handling.

## Key passages

- Lines 769-790 document and implement extension-command handling in `prompt()`: slash-prefixed input calls `_tryExecuteExtensionCommand()` before input events and returns without sending an LLM prompt when handled.
- Lines 901-924 parse the command name/args, resolve it via the extension runner, create `ExtensionCommandContext`, and await the registered handler.
- Lines 961-985 state and enforce that queued `steer()`/`followUp()` paths reject extension commands.
- Lines 1079-1113 implement extension-side `sendUserMessage()` by calling `prompt()` with `expandPromptTemplates: false`; line 1107 explicitly says this skips command handling and template expansion.

## Structural metadata

- Source type: installed compiled SDK runtime
- Relevant methods: `AgentSession.prompt`, `_tryExecuteExtensionCommand`, `sendUserMessage`
