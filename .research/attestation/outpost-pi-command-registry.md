---
source_handle: outpost-pi-command-registry
fetched: 2026-08-26
source_path: pi-extension/src/index.ts
provenance: source-direct
substrate_confidence: source-direct
---

# Outpost-Pi registered command registry

Paraphrased summary: Outpost-Pi registers one root command and twenty named subcommand adapters. The concrete handler calls in the registry pass only UI/cwd-shaped contexts to the actual operations; none calls a command-only SDK method. The wrapper still captures the received `ExtensionCommandContext` for unrelated session-action capability reuse.

## Key passages

- Lines 1784-1810 define `_rememberCommandCtx` and `runWithCtx`: every registered slash-command call captures the real command context, then forwards a stale-safe context to the operation.
- Lines 1813-1834 are the canonical twenty-subcommand registry: setup, hot-reload, status, stop, pair, devices, revoke, set-relay, peers, create, remove, daemons, five daemon operations, cron, install, and uninstall.
- Lines 1836-1852 register the root dispatcher, use longest-suffix matching, and call the same spec operations.
- Lines 1895-1947 type status/peers/root/setup against `Pick<ExtensionContext, "ui">` or `Pick<ExtensionContext, "ui" | "cwd">`.
- Lines 2095-2129 type start/pair/stop/devices/revoke/set-relay against the same base-context subsets.
- Lines 2923-2971 type hot-reload against `Pick<ExtensionContext, "ui">`.

## Structural metadata

- Source type: current Outpost-Pi TypeScript source
- Relevant region: command registration and top-level adapters
