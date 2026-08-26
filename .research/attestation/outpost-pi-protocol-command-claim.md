---
source_handle: outpost-pi-protocol-command-claim
fetched: 2026-08-26
source_path: PROTOCOL.md
provenance: source-direct
substrate_confidence: source-direct
---

# Current Outpost-Pi protocol claim about generic commands

Paraphrased summary: The current durable protocol says the old `@mariozechner/pi-coding-agent` SDK has no generic built-in slash-command invocation API and therefore justifies typed mobile actions. That remains correct for built-in TUI-only commands and for the absence of a direct named `invokeCommand` API, but it is incomplete for current extension commands because Pi 0.80.6 exposes prompt-based extension command execution and discovery.

## Key passages

- Lines 317-321 justify typed actions over a generic picker and name the old `@mariozechner/pi-coding-agent` package.
- Line 319 specifically discusses built-in slash commands such as compact/model/fork/copy, not extension-owned registered commands.

## Structural metadata

- Source type: current durable project protocol documentation
- Relationship to this engagement: overlapping prior claim; used as a lens to test, not as evidence for the SDK surface
