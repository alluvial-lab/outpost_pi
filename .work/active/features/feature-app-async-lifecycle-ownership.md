---
id: feature-app-async-lifecycle-ownership
kind: feature
stage: drafting
tags: [app, lifecycle]
parent: epic-remote-session-resilience-refactor
depends_on: []
release_binding: null
gate_origin: refactor
created: 2026-07-15
updated: 2026-07-17
---

# App: explicit ownership and observability for discarded async work

## Brief

Eleven gate findings across `app/` describe the same defect class: the mobile
app launches, retries, and persists through async futures that are never
awaited, returned, or given error handling. Failures vanish silently, which
breaks lifecycle convergence (the `working` state does not reliably settle
false on error) and masks the exact reconnect/persistence bugs the
`epic-remote-session-resilience-refactor` exists to fix. This feature
establishes explicit ownership — `unawaited(...).catchError(...)` or an owned
async boundary — for every discarded app-side future:

- `gate-cruft-dynamic-setactiveroom-fallback` — silent dynamic transport fallback for `setActiveRoom`
- `gate-cruft-empty-catch-old-channel-close` — empty catch around old channel close during adopt
- `gate-cruft-enqueue-drops-write-errors` — `_enqueue` drops write-chain exceptions
- `gate-cruft-room-adoption-persist-dropped` — legacy room-adoption persistence failures dropped
- `gate-refactor-lifecycle-app-router-floating-boot` — router starts `ConnectionManager.boot` as an unguarded future
- `gate-refactor-lifecycle-chat-bootstrap-floating` — `ChatViewModel` constructor discards bootstrap failures
- `gate-refactor-lifecycle-connection-retry-floating` — connection retry timer discards the reconnect future
- `gate-refactor-lifecycle-peer-mesh-publish-dropped` — peer mutation hook drops async mesh publish failures
- `gate-refactor-lifecycle-room-persist-fire-and-forget` — room persistence writes are fire-and-forget
- `gate-refactor-lifecycle-sync-service-floating-rebinds` — `SyncService` drops lifecycle-sensitive async rebind futures
- `gate-refactor-lifecycle-transcript-write-futures-discarded` — transcript write futures discarded from server-message handlers

## Simplification opportunity

Converge `working`/connection state to false on every error exit path (the
lifecycle-ownership rule in `.agents/rules/code-design.md`); the discarded
futures are the structural reason the state machine doesn't converge on
failure. No public-surface behavior change.

## Source

Promoted from backlog by `scope` (2026-07-15) as a child of
`epic-remote-session-resilience-refactor` — mobile UI state robustness is the
epic's stated scope. 11 `gate-refactor-lifecycle-*` / `gate-cruft-*` findings
from the v0.6.0 release `gate-refactor` (lifecycle library) and `gate-cruft` passes.

## Misroute note (2026-07-16 refactor-design pass)

**Retagged `[refactor]` → feature-design.** A fresh-context refactor-design
pass found the feature's central goals — surfacing previously ignored
failures, adding retry/recovery, converging UI/connection state after
failure — change observable error and lifecycle behavior. The `[refactor]`
black-box test fails for 4 of 6 steps. Two preliminary steps remain valid
pure refactors (Step 1 typed active-room capability, Step 2 best-effort
ownership cleanup) and should be executed first as quick wins within
feature-design. A global `unawaited(...).catchError(...)` utility should NOT
be introduced — error recovery differs between boot, connection retry,
transcript persistence, mesh publication, and teardown; prefer
owner-local boundaries.

The brief's claim that all eleven findings directly prevent `working` from
settling false is **not supported by current code** — `ErrorMessage` and
terminal handlers synchronously idle the turn, and
`app/test/data/sync/sync_service_test.dart:1988-2070` verifies convergence.
Several findings concern diagnostics, cold-start persistence, or ordering
rather than the live `working` flag. feature-design must re-validate each.

Parent-link note: `epic-remote-session-resilience-refactor`'s body cautions
against adding new refactor-scale work there; feature-design should confirm
this feature's parent assignment during its own pass.

## Refactor Overview

### Five-lens scan summary

- **Elimination First:** remove dynamic dispatch catches, redundant `Future(() async { ... })`, no-op `.then((_) {})`, and lint suppressions where ownership is already explicit.
- **Code Smells:** `SyncService` is a large multi-responsibility module, but splitting it is outside this focused feature and would increase risk.
- **Missing Abstractions:** the app lacks a typed optional active-room capability and owner-local async boundaries for serialized writes/rebinds.
- **Pattern Violations:** discarded futures violate lifecycle ownership; dynamic room targeting violates typed-boundary guidance.
- **Dead Weight:** the lint ignores and `_storage.savePeer(...).then((_) {})` are removable. A new app-wide generic future helper would add more concept than value.

## Refactor Steps

### Step 1: Replace dynamic active-room dispatch with a typed optional capability
**Priority:** High
**Risk:** Low
**Source Lens:** Missing abstraction / pattern drift
**Files:** `app/lib/data/transport/channel.dart`, `app/lib/data/transport/connection_manager.dart`, `app/lib/data/transport/peer_channel.dart`, `app/lib/data/transport/ws_transport.dart`, `app/lib/pairing/pair_request_flow.dart`, `app/test/data/transport/connection_manager_test.dart`, `app/test/pairing/pair_request_flow_test.dart`
**Stories covered:** `gate-cruft-dynamic-setactiveroom-fallback`

**Current State:**
```dart
// connection_manager.dart:302-312
void _propagateActiveRoom(String roomId, IChannel link) {
  try {
    (link as dynamic).setActiveRoom(roomId);
  } catch (_) {
    // Tests / non-WS transports — fine to ignore.
  }
}
```
The same dynamic/catch pattern exists in `peer_channel.dart:65-71` and `pair_request_flow.dart:114-120`. `IChannel` exposes only `serverMessages`, `send`, `close`.

**Target State:**
```dart
abstract interface class IActiveRoomTarget {
  void setActiveRoom(String roomId);
}

void _propagateActiveRoom(String roomId, IChannel link) {
  if (link is IActiveRoomTarget) {
    link.setActiveRoom(roomId);
  }
}
```
`PlainPeerChannel` and `WsTransport` implement `IActiveRoomTarget`; pairing and channel adapters test the capability rather than relying on dynamic duck typing.

**Implementation Notes:**
- Keep this capability optional so in-memory test transports remain valid without room targeting.
- Update `_RecordingChannel` in `connection_manager_test.dart:57-65` to implement the capability explicitly.
- Preserve the existing unsupported-transport no-op behavior. Do not add logging in this step.
- Do not make `setActiveRoom` mandatory on every `IChannel` or `PeerTransport`.

**Acceptance Criteria:**
- [ ] No `dynamic` call to `setActiveRoom` remains in `app/lib/`.
- [ ] Unsupported transports remain silent no-ops.
- [ ] Existing active-room propagation tests at `connection_manager_test.dart:261-297` still pass.
- [ ] `flutter analyze` passes without new ignores.
- [ ] `flutter test test/data/transport/connection_manager_test.dart test/pairing/pair_request_flow_test.dart` passes.
- [ ] No protocol shape, routing timing, or user-visible behavior changes.

**Rollback:** Revert the capability interface and restore the three dynamic calls as one isolated commit.

### Step 2: Normalize already-owned best-effort work without changing failure policy
**Priority:** Medium
**Risk:** Low
**Source Lens:** Elimination / dead weight / pattern drift
**Files:** `app/lib/data/transport/connection_manager.dart`, `app/test/data/transport/connection_manager_test.dart`
**Stories covered:** pure portion of `gate-cruft-empty-catch-old-channel-close`, pure portion of `gate-cruft-room-adoption-persist-dropped`, structural portion of `gate-refactor-lifecycle-connection-retry-floating`

**Current State:**
```dart
// connection_manager.dart:473-478
Future(() async {
  try {
    await old.close();
  } catch (_) {}
});

// connection_manager.dart:1222-1226
_storage.savePeer(updated).then((_) {}).catchError((Object e, StackTrace _) {});

// connection_manager.dart:1317-1321
_retryTimer = Timer(delay, () {
  _retryTimer = null;
  _reachability.onRetryTimerFired();
  _connect(peer);
});
```
Expected connect failures are already owned by `_connect` (`573-626`), which catches and schedules retry.

**Target State:**
```dart
void _closeBestEffort(IChannel channel) {
  unawaited(channel.close().catchError((Object _, StackTrace __) {}));
}
// adopt: _closeBestEffort(old);
// legacy-room migration: preserve the existing non-fatal swallow
unawaited(_storage.savePeer(updated).catchError((Object _, StackTrace __) {}));
// retry: expected failures are handled inside _connect
unawaited(_connect(peer));
```

**Implementation Notes:**
- Reuse `_closeBestEffort` from both `adopt` and synchronous `dispose`; do not add a global future utility.
- Remove the redundant `Future` allocation and `.then((_) {})`.
- Keep the exact current failure policy: close and migration-persistence failures remain non-fatal and unreported.
- Add a short comment at the retry call explaining that `_connect` owns expected failure-to-retry conversion.
- Any request to log these failures belongs in Step 4 (feature-design).

**Acceptance Criteria:**
- [ ] The old channel still closes asynchronously without delaying `adopt`.
- [ ] A close failure does not block adoption or disposal.
- [ ] Legacy-room persistence remains non-fatal.
- [ ] Retry timing, attempt count, and status transitions are unchanged.
- [ ] The three local lint suppressions and no-op `.then` are removed.
- [ ] `flutter analyze` and `flutter test test/data/transport/connection_manager_test.dart` pass.

**Rollback:** Revert the local helper and restore each prior inline expression; no data migration is involved.

### Step 3: Retag startup initialization ownership for feature-design
**Priority:** High
**Risk:** High
**Source Lens:** Lifecycle pattern violation / missing owned boundary
**Files:** `app/lib/routing/app_router.dart`, `app/lib/ui/chat/viewmodels/chat_viewmodel.dart`, `app/lib/ui/chat/states/chat_state.dart` (if a new error state is chosen), `app/test/ui/chat/chat_viewmodel_test.dart`, router/bootstrap tests to be added by feature-design
**Stories covered:** `gate-refactor-lifecycle-app-router-floating-boot`, `gate-refactor-lifecycle-chat-bootstrap-floating`

**Current State:**
```dart
// app_router.dart:118-119
conn.boot(preferredEpk: selected);
// app_router.dart:171-178
boot.load(...);
// chat_viewmodel.dart:73-74
_bootstrap();
```
`_BootState.load` marks itself ready before starting the connection (`app_router.dart:100-119`). `ChatViewModel._bootstrap` performs storage load, connection switching, sync activation, and subscription binding (`chat_viewmodel.dart:118-180`).

**Target State:**
```text
RETAG FOR FEATURE-DESIGN — do not implement as a pure refactor.

Feature-design must choose and test:
1. Whether router readiness includes completion of ConnectionManager.boot.
2. What route/state is shown when preferences, identity, storage, or connection boot fails.
3. Whether ChatViewModel exposes an awaited initialize() boundary or catches constructor-started bootstrap internally.
4. Which existing or new ChatState represents bootstrap failure.
5. How dispose/session replacement invalidates an in-flight bootstrap.
```

**Implementation Notes:**
- Do not merely attach an empty `catchError`; that could suppress errors currently delivered to the zone while leaving the UI stuck.
- If router connection boot remains background work, its owner must define explicit recovery and stale-run guards.
- If chat initialization stays constructor-started, `_bootstrap` itself must catch failures, verify `_disposed`, and emit a chosen terminal/retry state.
- The rooms-stream call at `chat_viewmodel.dart:69` also launches `_refreshSessionBinding` and should follow the same owner policy.

**Acceptance Criteria:**
- [ ] Router boot failure has a specified recoverable state and does not leave `/boot` permanently unresolved.
- [ ] Chat bootstrap failure has a specified UI state and cannot publish after disposal.
- [ ] Tests cover disposal during bootstrap and storage/activation failure.
- [ ] Existing successful bootstrap behavior remains covered.
- [ ] Full `flutter analyze` and `flutter test` pass.

### Step 4: Retag ConnectionManager persistence and teardown observability
**Priority:** High
**Risk:** Medium
**Source Lens:** Lifecycle ownership / missing owner-local abstraction
**Files:** `app/lib/data/transport/connection_manager.dart`, `app/lib/domain/contracts/debug_log.dart` (if diagnostics are selected), `app/test/data/transport/connection_manager_test.dart`, `app/test/domain/contracts/debug_log_test.dart` (if a diagnostic variant is added)
**Stories covered:** behavioral portion of `gate-cruft-empty-catch-old-channel-close`, behavioral portion of `gate-cruft-room-adoption-persist-dropped`, `gate-refactor-lifecycle-room-persist-fire-and-forget`, optional unexpected-error portion of `gate-refactor-lifecycle-connection-retry-floating`

**Current State:** Room writes are launched independently at `connection_manager.dart:744,816,873,1032,1044,1080`. `_persistRoomsForPeer` performs several async reads before writing at `1115-1150`, so overlapping calls can complete out of order and survive service disposal. Legacy room adoption explicitly swallows save failure at `1218-1226`.

**Target State:**
```text
RETAG FOR FEATURE-DESIGN.

Define one ConnectionManager-owned policy for:
- per-peer room-write serialization/coalescing;
- stale/disposed checks before final persistence;
- close-failure diagnostics while adoption remains non-blocking;
- legacy-room save retry or explicit non-retry diagnostics;
- unexpected retry-loop failures.
```

**Implementation Notes:**
- A private per-peer persistence boundary is preferable to a global future helper.
- Preserve current immediate in-memory room projection unless feature-design explicitly chooses rollback on persistence failure.
- Persisted rooms currently do not restore `working`; this finding primarily affects cached room metadata and cold-start consistency.
- If adding a `DebugEvent`, use a typed, privacy-safe variant rather than free-form messages.
- Do not block synchronous `dispose` waiting for storage/network completion.

**Acceptance Criteria:**
- [ ] Every room-persistence launch routes through one ConnectionManager-owned boundary.
- [ ] Two rapid updates for one peer cannot persist an older snapshot after a newer one.
- [ ] Teardown behavior for pending persistence is explicitly specified and tested.
- [ ] Close and migration failures follow the chosen diagnostic/retry policy.
- [ ] Reconnect and room-working projection tests remain green.
- [ ] `flutter analyze`, targeted connection tests, and full `flutter test` pass.

### Step 5: Retag SyncService write, rebind, and transcript failure semantics
**Priority:** High
**Risk:** High
**Source Lens:** Missing abstraction / lifecycle ownership / code smell
**Files:** `app/lib/data/sync/sync_service.dart`, `app/lib/domain/contracts/debug_log.dart` (if diagnostics are added), `app/test/data/sync/sync_service_test.dart`, `app/test/data/sync/session_history_replay_test.dart`, `app/test/ui/chat/chat_viewmodel_test.dart`
**Stories covered:** `gate-cruft-enqueue-drops-write-errors`, `gate-refactor-lifecycle-sync-service-floating-rebinds`, `gate-refactor-lifecycle-transcript-write-futures-discarded`

**Current State:**
```dart
// sync_service.dart:1741-1744
Future<void> _enqueue(Future<void> Function() op) {
  final next = _writeChain.then((_) => op());
  _writeChain = next.catchError((Object _, StackTrace _) {});
  return next;
}
```
Transcript handlers enqueue writes without awaiting them at `sync_service.dart:817-1181`. Rebind and lifecycle work is independently launched at `430,455,653,697,709,1129,1134`. `_writeRuntime` also fails to await Hive's `put` inside its supposedly serialized closure at `1713-1720`.

**Target State:**
```text
RETAG FOR FEATURE-DESIGN.

Create SyncService-owned boundaries that distinguish:
1. Awaited commands — caller receives persistence failure.
2. Detached serialized writes — queue remains alive, failure is diagnosed, and the chosen state-convergence action runs.
3. Ordering-critical lifecycle work — activation/rebind completes before resend, replay, or subsequent session-dependent work.
4. Stale-session work — exits after every async gap without mutating the replacement session.
```

**Implementation Notes:**
- Keep `_enqueue` as the single write serializer, but make the detached error policy explicit and named.
- Await `_boxes.runtimeBox().put(...)` inside the queued operation; this changes serialization behavior and therefore belongs here, not in the pure steps.
- Do not turn stream listeners into bare `async` callbacks; stream delivery does not await them.
- Activation triggered by `_onRoomsChanged` must complete before `_resendHeldPendingMessages` if that ordering is selected.
- Server-message handlers need one consistent transcript-write entrypoint rather than thirteen repeated lint suppressions.
- Preserve stale-session checks around `RemoteSessionRef`.
- Existing convergence coverage at `sync_service_test.dart:1988-2070` is useful but does not inject event-store/Hive failures; add failing-adapter tests.

**Acceptance Criteria:**
- [ ] No `discarded_futures` suppression remains in `SyncService`.
- [ ] Every detached operation is routed through a named owner boundary.
- [ ] The write queue continues accepting later operations after one failure.
- [ ] Runtime-box writes are actually part of queue completion.
- [ ] Rebind/resend/replay ordering is deterministic and covered by tests.
- [ ] Injected transcript-write failure follows the selected observable policy and leaves `working` converged as specified.
- [ ] Old-session writes cannot land in the replacement session.
- [ ] `flutter analyze`, targeted sync/chat tests, and full `flutter test` pass.

### Step 6: Retag mesh mutation publication ownership
**Priority:** Medium
**Risk:** Medium
**Source Lens:** Ports and adapters / lifecycle ownership
**Files:** `app/lib/config/dependencies.dart`, `app/lib/data/mesh/mesh_sync_service.dart`, `app/lib/pairing/storage.dart`, `app/test/data/mesh/mesh_sync_service_test.dart`, `app/test/pairing/storage_test.dart`
**Stories covered:** `gate-refactor-lifecycle-peer-mesh-publish-dropped`

**Current State:**
```dart
// dependencies.dart:118-120
_storage.attachPeerMutationHook(() {
  meshSync.publish();
});
```
`PairingStorage` deliberately defines a synchronous post-commit hook at `storage.dart:204-224`. `MeshSyncService.publish` returns typed failure variants at `mesh_sync_service.dart:176-194,241-261`; routine failures generally do not throw.

**Target State:**
```text
RETAG FOR FEATURE-DESIGN.

Move post-mutation publication ownership into MeshSyncService, for example a
publishAfterPeerMutation boundary that:
- awaits publish internally;
- inspects MeshPublishResult rather than only catching exceptions;
- applies the selected diagnostic/reconciliation policy;
- catches unexpected storage/crypto/network exceptions;
- preserves PairingStorage's local-write-first, non-blocking contract.
```

**Implementation Notes:**
- Keep `PairingStorage` independent of mesh/network implementation details.
- Do not make `savePeer` await relay publication; that would change its local-first contract and couple storage availability to network availability.
- Decide whether typed publish failure merely records diagnostics, schedules a pull, or queues a retry. Each is behavior-changing.
- Preserve the existing empty-members safety net and `_publishing` stampede guard.

**Acceptance Criteria:**
- [ ] The DI callback delegates to an explicitly owned MeshSyncService boundary.
- [ ] Every `MeshPublishResult` variant has an intentional disposition.
- [ ] Unexpected exceptions do not escape an unowned future.
- [ ] Local peer mutation still completes before background publication.
- [ ] Pull/apply does not re-enter publish.
- [ ] Existing publish-race, conflict, and empty-members tests remain green.
- [ ] New tests cover the selected typed-failure and thrown-error policies.
- [ ] `flutter analyze` and full `flutter test` pass.

## Implementation Order

1. **Retag done:** `refactor` removed from tags; feature routes to feature-design.
2. **Step 1:** typed active-room capability (pure refactor — quick win).
3. **Step 2:** behavior-preserving best-effort ownership cleanup (pure refactor — quick win).
4. **Step 3:** router and ChatViewModel startup ownership (feature-design).
5. **Step 4:** ConnectionManager persistence/teardown policy (feature-design).
6. **Step 5:** SyncService serialization, rebind ordering, transcript failure, convergence policy (feature-design).
7. **Step 6:** mesh mutation publication ownership (feature-design).
8. Verify from `app/`: `flutter analyze`, `flutter test`, then `flutter build apk --debug` smoke if the environment permits.
