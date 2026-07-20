---
name: patterns
description: "Project code patterns and conventions. Auto-loads when implementing,
  designing, verifying, or reviewing code. Provides detailed pattern definitions
  with code examples."
user-invocable: false
allowed-tools: Read, Glob, Grep
---

# Project Patterns Reference

This skill contains detailed pattern documentation for this project.
See individual pattern files for full details with code examples.

Available patterns:
- [command-surface-adapter-classes.md](command-surface-adapter-classes.md) — Keep command-surface logic in thin, dependency-injected adapter classes.
- [typed-wire-decoders.md](typed-wire-decoders.md) — Parse/validate untrusted wire text through shared decode helpers before routing typed handlers.
- [subscription-unsubscribe-contract.md](subscription-unsubscribe-contract.md) — Return unsubscribe closures for event handlers and keep callback registration/teardown explicit.
- [snapshot-replay-event-mappers.md](snapshot-replay-event-mappers.md) — Convert snapshot payloads into canonical transcript event streams before projection.
- [single-source-live-identity.md](single-source-live-identity.md) — When adding a deterministic-identity live broadcast, remove or guard the legacy broadcast it replaces, or both survive as duplicate Hive rows.
- [reachability-contract-projection.md](reachability-contract-projection.md) — Project the reachability contract into stack-specific enums and clamped helper logic.
- [centralized-resource-policy.md](centralized-resource-policy.md) — Define relay resource ceilings and budget semantics once, then import them at each owning boundary.
- [generation-fenced-async-ownership.md](generation-fenced-async-ownership.md) — Capture a lifecycle revision before async work and suppress side effects when the owner has been replaced or disposed.
