---
id: feature-app-async-lifecycle-ownership-startup-ownership
kind: story
stage: done
tags: [app, lifecycle]
parent: feature-app-async-lifecycle-ownership
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-17
updated: 2026-07-17
---

# Own router and Chat startup failures

## Checkpoint

Implement Unit 3 from the parent feature: make router boot and Chat session
initialization generation-guarded, awaited at their owning boundary, recoverable,
and incapable of publishing after retry/session replacement/disposal.

## Finding coverage

- `gate-refactor-lifecycle-app-router-floating-boot`
- `gate-refactor-lifecycle-chat-bootstrap-floating`

## Required behavior

- Router readiness awaits the initial `ConnectionManager.boot` attempt but not
  eventual online reachability.
- Preferences, unexpected identity, storage, and bootstrap exceptions remain on
  `/boot` with a safe Retry action; sync unavailable keeps `/sync-required`.
- `ChatViewModel.initialize()` owns all failures and emits
  `ChatInitializationFailed`; Retry can await the same method.
- Initial and room-driven rebinds share one serialized generation-guarded path.
- Stale runs cannot emit, install a watcher/subscription, or retain old-session
  rows.

## Acceptance evidence

- [x] Router tests cover each failing phase, retry success, network retry state,
      and invalidated run completion.
- [x] Chat tests cover storage/activation failure, disposal during bootstrap,
      retry, and rebind failure after session replacement.
- [x] Successful boot, sync-required, no-peer, and normal Chat initialization
      remain green.
- [x] Targeted tests and `flutter analyze` pass.

## Implementation

- Execution capability: inline, high-rigor lifecycle implementation; one owner
  retained router/Chat generation context end to end.
- Review weight: standard (caller workflow default; feature-level review only).
- Files changed: `app_router.dart`, Chat state/ViewModel/page, router and Chat
  lifecycle tests.
- Tests added: boot phase/retry/stale-run/disposal coverage plus Chat
  load/activation/rebind/disposal failure coverage.
- Simplification: constructor and room-stream discarded futures now terminate in
  explicit owner-local boundaries; stale session subscriptions are cleared.
- Discrepancies from design: `BootState` is public within the routing library so
  tests exercise the real readiness boundary without constructing all Home DI;
  it is not re-exported as an app API.
- Adjacent issues parked: none.

Verification: `flutter test test/routing/app_router_test.dart
 test/ui/chat/chat_viewmodel_test.dart` and `flutter analyze lib test` passed.
