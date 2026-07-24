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
- [content-free-diagnostic-categories.md](content-free-diagnostic-categories.md) — Project boundary failures to closed reason codes and bounded metadata before logging; never persist raw payloads or arbitrary error text.
- [frame-byte-bounded-admission.md](frame-byte-bounded-admission.md) — Check count and retained-byte budgets before enqueueing burst-controlled work, then release both counters on every exit path.
- [identity-scoped-monotonic-high-watermarks.md](identity-scoped-monotonic-high-watermarks.md) — Advance security watermarks only under their matching owner/key generation and never permit stale or lower values to win.
- [recoverable-secure-channel-circuit-breakers.md](recoverable-secure-channel-circuit-breakers.md) — Detach after a bounded invalid-frame streak, retain valid persisted keys, and recover through authenticated reattach plus state synchronization.
- [cross-language-known-answer-fixture-triangulation.md](cross-language-known-answer-fixture-triangulation.md) — Generate one deterministic protocol fixture independently and require every language endpoint to reproduce it byte-for-byte.
- [command-surface-adapter-classes.md](command-surface-adapter-classes.md) — Keep command-surface logic in thin, dependency-injected adapter classes.
- [typed-wire-decoders.md](typed-wire-decoders.md) — Parse/validate untrusted wire text through shared decode helpers before routing typed handlers.
- [subscription-unsubscribe-contract.md](subscription-unsubscribe-contract.md) — Return unsubscribe closures for event handlers and keep callback registration/teardown explicit.
- [snapshot-replay-event-mappers.md](snapshot-replay-event-mappers.md) — Convert snapshot payloads into canonical transcript event streams before projection.
- [single-source-live-identity.md](single-source-live-identity.md) — When adding a deterministic-identity live broadcast, remove or guard the legacy broadcast it replaces, or both survive as duplicate Hive rows.
- [reachability-contract-projection.md](reachability-contract-projection.md) — Project the reachability contract into stack-specific enums and clamped helper logic.
- [centralized-resource-policy.md](centralized-resource-policy.md) — Define relay resource ceilings and budget semantics once, then import them at each owning boundary.
- [generation-fenced-async-ownership.md](generation-fenced-async-ownership.md) — Capture a lifecycle revision before async work and suppress side effects when the owner has been replaced or disposed.
- [awaited-pane-teardown-contract.md](awaited-pane-teardown-contract.md) — Remove pane ownership before awaiting teardown, and expose a Future that completes only after its resources close.
- [stale-capability-eviction.md](stale-capability-eviction.md) — On a Pi stale-context error, evict only the matching captured capability before degrading or propagating the failure.
- [fresh-operation-gateway-factories.md](fresh-operation-gateway-factories.md) — Create a fresh, lifecycle-owned gateway through an injected factory for each independent process, agent, terminal, or pairing operation.
