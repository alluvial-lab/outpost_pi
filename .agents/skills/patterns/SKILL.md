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
- [lifecycle-boundary-state-convergence.md](lifecycle-boundary-state-convergence.md) — Reset active lifecycle projections before transport teardown so replacement and shutdown cannot strand stale state.
- [durable-first-visibility-gating.md](durable-first-visibility-gating.md) — Append canonical transcript facts before publishing replayable live visibility, and gate on recorded or duplicate authority.
- [presence-aware-patch-merging.md](presence-aware-patch-merging.md) — Distinguish omitted patch fields from explicit values so partial updates preserve cached state.
- [edge-triggered-convergence.md](edge-triggered-convergence.md) — Notify, persist, or publish only when a validated semantic projection changes.
- [session-scoped-derived-identity.md](session-scoped-derived-identity.md) — Include canonical session identity in transcript reads, writes, dedupe indexes, and derived reply links.
- [era-aware-authority-fallback-binding.md](era-aware-authority-fallback-binding.md) — Prefer durable facts, then bind only unmatched legacy facts by stable collision keys for mixed-era compatibility.
- [canonical-projection-equivalence-oracle.md](canonical-projection-equivalence-oracle.md) — Compare optimized or migrated projections with an independent canonical oracle over prefixes, duplicates, and reopen cases.
- [content-free-diagnostic-categories.md](content-free-diagnostic-categories.md) — Project boundary failures to closed reason codes and bounded metadata before logging; never persist raw payloads or arbitrary error text.
- [frame-byte-bounded-admission.md](frame-byte-bounded-admission.md) — Check count and retained-byte budgets before enqueueing burst-controlled work, then release both counters on every exit path.
- [identity-scoped-monotonic-high-watermarks.md](identity-scoped-monotonic-high-watermarks.md) — Advance security watermarks only under their matching owner/key generation and never permit stale or lower values to win.
- [recoverable-secure-channel-circuit-breakers.md](recoverable-secure-channel-circuit-breakers.md) — Detach after a bounded invalid-frame streak, retain valid persisted keys, and recover through authenticated reattach plus state synchronization.
- [cross-language-known-answer-fixture-triangulation.md](cross-language-known-answer-fixture-triangulation.md) — Generate one deterministic protocol fixture independently and require every language endpoint to reproduce it byte-for-byte.
- [durable-transition-latches.md](durable-transition-latches.md) — Persist a pending latch before destructive cleanup, gate access while latched, resume at boot, and clear only after commit.
- [explicit-async-interleaving-tests.md](explicit-async-interleaving-tests.md) — Test async ordering through explicit started/release barriers in fakes or harnesses, never elapsed time.
- [deterministic-completion-barriers.md](deterministic-completion-barriers.md) — Drain event-loop work or await a named bounded state predicate instead of using arbitrary sleeps for async test completion.
- [failure-first-regression-tests.md](failure-first-regression-tests.md) — Start from the old failure boundary, assert the observable invariant, then verify repaired transitions.
- [break-it-proof-regression-discipline.md](break-it-proof-regression-discipline.md) — Reintroduce one old failure, require the guard to fail with bounded evidence, then restore and rerun the clean path.
- [golden-render-saving-comparators.md](golden-render-saving-comparators.md) — Capture through `matchesGoldenFile` with a saving comparator, then reject missing or blank evidence.
- [e2e-selector-harness-scenarios.md](e2e-selector-harness-scenarios.md) — Map checked-in live-test selectors in the runner and let each harness scenario own setup, assertions, phases, and teardown.
- [generated-protocol-constant-consumption.md](generated-protocol-constant-consumption.md) — Consume generated protocol registries and limits at every language boundary instead of copying wire facts.
- [owner-channel-scoped-resource-ownership.md](owner-channel-scoped-resource-ownership.md) — Bind retained resources to both owner identity and concrete channel, and tear down every matching index together.
- [asymmetric-threshold-stabilization.md](asymmetric-threshold-stabilization.md) — Use separate entry/exit conditions or consecutive healthy probes to prevent noisy state flapping.
- [command-surface-adapter-classes.md](command-surface-adapter-classes.md) — Keep command-surface logic in thin, dependency-injected adapter classes.
- [typed-wire-decoders.md](typed-wire-decoders.md) — Parse/validate untrusted wire text through shared decode helpers before routing typed handlers.
- [event-bus-unknown-payload-narrowing.md](event-bus-unknown-payload-narrowing.md) — Narrow unknown event-bus payloads to validated fields before mutating lifecycle state.
- [subscription-unsubscribe-contract.md](subscription-unsubscribe-contract.md) — Return unsubscribe closures for event handlers and keep callback registration/teardown explicit.
- [snapshot-replay-event-mappers.md](snapshot-replay-event-mappers.md) — Convert snapshot payloads into canonical transcript event streams before projection.
- [single-source-live-identity.md](single-source-live-identity.md) — When adding a deterministic-identity live broadcast, remove or guard the legacy broadcast it replaces, or both survive as duplicate Hive rows.
- [reachability-contract-projection.md](reachability-contract-projection.md) — Project the reachability contract into stack-specific enums and clamped helper logic.
- [reachable-blob-history-content-scanning.md](reachable-blob-history-content-scanning.md) — Enumerate unique blobs reachable from public revisions and scan their bytes directly, including merge and binary history.
- [centralized-resource-policy.md](centralized-resource-policy.md) — Define relay resource ceilings and budget semantics once, then import them at each owning boundary.
- [generation-fenced-async-ownership.md](generation-fenced-async-ownership.md) — Capture a lifecycle revision before async work and suppress side effects when the owner has been replaced or disposed.
- [awaited-pane-teardown-contract.md](awaited-pane-teardown-contract.md) — Remove pane ownership before awaiting teardown, and expose a Future that completes only after its resources close.
- [stale-capability-eviction.md](stale-capability-eviction.md) — On a Pi stale-context error, evict only the matching captured capability before degrading or propagating the failure.
- [fresh-operation-gateway-factories.md](fresh-operation-gateway-factories.md) — Create a fresh, lifecycle-owned gateway through an injected factory for each independent process, agent, terminal, or pairing operation.
- [atomic-snapshot-store-marker-last-migration.md](atomic-snapshot-store-marker-last-migration.md) — Flush complete snapshots through temp-and-rename, and write a migration completion marker only after all destinations finish.
- [dual-execution-path-contract-documentation.md](dual-execution-path-contract-documentation.md) — Document capability-dependent operations as both in-process and managed-restart paths, including ownership, acknowledgement, teardown, and convergence.
- [paired-brightness-semantic-palettes.md](paired-brightness-semantic-palettes.md) — Define semantic color roles as complete dark/light pairs and resolve brightness once at each surface's composition boundary, never in leaf components.
- [canonical-mark-rasterization-fanout.md](canonical-mark-rasterization-fanout.md) — Render one canonical brand geometry through a single supersampled renderer and fan it out to every platform-specific raster asset.
