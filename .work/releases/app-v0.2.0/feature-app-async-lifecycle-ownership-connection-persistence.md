---
id: feature-app-async-lifecycle-ownership-connection-persistence
kind: story
stage: done
tags: [app, lifecycle]
parent: feature-app-async-lifecycle-ownership
depends_on: [feature-app-async-lifecycle-ownership-startup-ownership]
release_binding: app-v0.2.0
gate_origin: null
created: 2026-07-17
updated: 2026-07-20
---

# Serialize ConnectionManager persistence and diagnose teardown failures

## Checkpoint

Implement Unit 4 from the parent feature: one latest-wins persistence drain per
peer, disposal/staleness checks before final writes, bounded legacy-room retry,
and privacy-safe diagnostics for close/persistence/unexpected retry failures.

## Finding coverage

- `gate-refactor-lifecycle-room-persist-fire-and-forget`
- behavioral portion of `gate-cruft-empty-catch-old-channel-close`
- behavioral portion of `gate-cruft-room-adoption-persist-dropped`
- unexpected-error portion of `gate-refactor-lifecycle-connection-retry-floating`

## Required behavior

- All room-cache mutations route through one per-peer coalescing boundary.
- A superseded or disposed drain does not start its final storage write.
- Ordinary cache failure is diagnosed and retries only on the next mutation;
  immediate in-memory state is preserved.
- Legacy room selection retries once because it is routing-critical.
- Close failure remains non-blocking; an unexpected reconnect escape is logged
  and left to the existing watchdog recovery path.
- The shared `LifecycleFailureEvent` obeys the debug log privacy registry.

## Acceptance evidence

- [x] Controlled completions prove older snapshots cannot land after newer ones
      for one peer and separate peers do not block each other.
- [x] Failing storage proves next-mutation retry and bounded legacy retry.
- [x] Close/retry failures emit the expected typed diagnostic without changing
      adoption/disposal/retry guarantees.
- [x] Debug event exhaustiveness, allow-list, clamp, and capture-site tests pass.
- [x] Targeted connection/debug tests and `flutter analyze` pass.

## Implementation

- Execution capability: inline, high-rigor persistence/lifecycle work to retain
  one ordering model across cache, retry, teardown, and diagnostics.
- Review weight: standard (caller workflow default; feature-level review only).
- Files changed: `connection_manager.dart`, typed debug contract, and focused
  connection/debug registry/capture tests.
- Tests added: per-peer latest-wins coalescing, peer independence,
  next-mutation retry, disposal guard, bounded legacy retry, and close capture.
- Simplification: six independent room-save launches now use one per-peer drain;
  silent close/retry/persistence failure paths share the typed diagnostic.
- Discrepancies from design: unexpected retry escape is owned and diagnosed by
  `_connectRetryOwned`; the factory's existing expected-error catch makes that
  escape unreachable through normal public test inputs.
- Adjacent issues parked: none.

Verification: focused connection/debug tests (39 tests) and
`flutter analyze lib test` passed.
