---
id: feature-app-async-lifecycle-ownership-connection-persistence
kind: story
stage: implementing
tags: [app, lifecycle]
parent: feature-app-async-lifecycle-ownership
depends_on: [feature-app-async-lifecycle-ownership-startup-ownership]
release_binding: null
gate_origin: null
created: 2026-07-17
updated: 2026-07-17
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

- [ ] Controlled completions prove older snapshots cannot land after newer ones
      for one peer and separate peers do not block each other.
- [ ] Failing storage proves next-mutation retry and bounded legacy retry.
- [ ] Close/retry failures emit the expected typed diagnostic without changing
      adoption/disposal/retry guarantees.
- [ ] Debug event exhaustiveness, allow-list, clamp, and capture-site tests pass.
- [ ] Targeted connection/debug tests and `flutter analyze` pass.
