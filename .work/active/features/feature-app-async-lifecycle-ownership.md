---
id: feature-app-async-lifecycle-ownership
kind: feature
stage: done
tags: [app, lifecycle]
parent: epic-remote-session-resilience-refactor
depends_on: []
release_binding: null
gate_origin: refactor
created: 2026-07-15
updated: 2026-07-18
reviewed: "2026-07-18 (standard, gpt-5.6-sol fresh-context → needs fixes; 6 findings fixed + verified → done; no second pass per standard weight)"
---

# App: explicit ownership and observability for discarded async work

## Brief

Eleven gate findings across `app/` describe the same defect class: the mobile
app launches, retries, and persists through async futures that are never
awaited, returned, or given error handling. Failures vanish silently. Some of
those paths can leave lifecycle state stale; others lose cold-start metadata or
hide a failed recovery attempt. This feature gives each discarded future an
owner-local policy rather than introducing an app-wide async helper.

The findings are:

- `gate-cruft-dynamic-setactiveroom-fallback`
- `gate-cruft-empty-catch-old-channel-close`
- `gate-cruft-enqueue-drops-write-errors`
- `gate-cruft-room-adoption-persist-dropped`
- `gate-refactor-lifecycle-app-router-floating-boot`
- `gate-refactor-lifecycle-chat-bootstrap-floating`
- `gate-refactor-lifecycle-connection-retry-floating`
- `gate-refactor-lifecycle-peer-mesh-publish-dropped`
- `gate-refactor-lifecycle-room-persist-fire-and-forget`
- `gate-refactor-lifecycle-sync-service-floating-rebinds`
- `gate-refactor-lifecycle-transcript-write-futures-discarded`

## Routing correction and parent fit

A refactor-design pass correctly removed the `[refactor]` tag. Startup recovery,
visible persistence degradation, retry policy, and failure-state convergence are
observable behavior changes. Two preliminary units remain behavior-preserving
quick wins.

The parent `epic-remote-session-resilience-refactor` cautions against new
refactor-scale work. The assignment remains sensible because this is a bounded
app-side resilience patch sourced from that epic's lifecycle findings, not a new
architecture arc. It does not split `SyncService`, replace the app state model,
or compete with the `epic-bold-*` reconception.

## Current-state verification

The refactor pass's mapping remains current on 2026-07-17:

- Router boot sets `_ready` before launching an unowned
  `ConnectionManager.boot` at `app/lib/routing/app_router.dart:102-119`; the
  top-level `boot.load(...)` is also discarded at `:171-178`.
- `ConnectionManager.boot` at
  `app/lib/data/transport/connection_manager.dart:395-438` awaits cache restore
  and the first connect attempt. Expected network failures are converted to
  retry state inside `_connect` (`:568-626`), so awaiting `boot` does not mean
  waiting until the peer is online.
- `ChatViewModel` launches `_bootstrap()` from its constructor at
  `app/lib/ui/chat/viewmodels/chat_viewmodel.dart:73-74`; room updates launch
  `_refreshSessionBinding()` at `:68-70`. Disposal guards exist after some
  awaits (`:127`, `:143`, `:149`, `:161`) but no failure owner exists.
- Room-cache persistence is launched independently at
  `connection_manager.dart:744,816,873,1032,1044,1080`; the write performs
  multiple reads before `saveRooms` at `:1115-1150`, so older writes can land
  after newer snapshots. Legacy-room persistence is swallowed at `:1222-1226`.
- `SyncService` independently launches online activation/rebind/resend at
  `app/lib/data/sync/sync_service.dart:653,697,709`, transcript work at
  `:817-1181`, and history replay at `:1134-1135`. `_enqueue` keeps its chain
  alive by swallowing the prior error at `:1741-1744`, while `_writeRuntime`
  fails to await Hive `put` at `:1713-1720`.
- Existing convergence coverage at
  `app/test/data/sync/sync_service_test.dart:1988-2070` proves success, protocol
  error, cancellation, compaction, and replay settle idle. It does not inject
  `TranscriptEventStore` or Hive write failures.
- `PairingStorage` deliberately exposes a synchronous post-commit hook at
  `app/lib/pairing/storage.dart:204-252`; DI discards `meshSync.publish()` at
  `app/lib/config/dependencies.dart:118-120`. `MeshSyncService.publish` returns
  typed outcomes at `app/lib/data/mesh/mesh_sync_service.dart:176-261`, so most
  failures do not throw. The last-peer revoke separately discards an explicit
  `publish(allowEmpty: true)` at
  `app/lib/ui/settings/viewmodels/settings_viewmodel.dart:118-134`.

The earlier brief overstated the `working` impact. Protocol terminal handlers
already set idle synchronously, and the cited tests prove that path. This design
keeps that guarantee while separately addressing startup, cache consistency,
write diagnostics, and replay recovery.

## Design decisions

- **Router readiness includes `ConnectionManager.boot` completion, not online
  reachability.** `_BootState.load` awaits the initial cache restore and connect
  attempt before routing to Home. Retryable relay failures still resolve
  `boot()` into `StatusRetrying`; the splash never waits for an online peer.
- **Boot failures stay on `/boot` with an inline Retry action.** Preferences,
  unexpected identity, peer/storage, and connection-bootstrap failures map to a
  private typed boot stage and a safe user message. `SyncUnavailableResult`
  keeps the existing `/sync-required` route. A normal relay/network failure is
  rendered later through `ConnectionStatus`, not as a boot failure.
- **Boot runs are generation-guarded.** Retry, Owner-key replacement, and
  disposal invalidate the previous run. Every async gap checks the run id before
  mutating router state or installing the identity watcher.
- **`ChatViewModel` exposes an awaited, idempotent `initialize()`.** Provider
  construction still starts it because Provider factories are synchronous, but
  the constructor uses `unawaited(initialize())` only because `initialize`
  catches and projects every failure. Tests and Retry UI can await the same
  method directly.
- **Chat bootstrap/rebind failure uses a new recoverable state, not
  `ChatFatalError`.** `ChatInitializationFailed` means the selected session
  could not be loaded or bound and offers Retry. `ChatFatalError` remains the
  re-pair-only state. A failed canonical-session rebind fails closed rather than
  continuing to display a possibly stale session projection.
- **Chat initialization is generation-guarded and serialized.** Dispose or a
  newer retry invalidates an in-flight storage/connection/sync run; subscriptions
  and state are installed only for the latest run. Room-driven rebinds share the
  same owned serialized boundary instead of racing constructor bootstrap.
- **Room-cache writes are per-peer, latest-wins drains.** A new request bumps a
  peer revision. One worker per peer reads and writes the latest snapshot; it
  skips a final write when disposed or superseded. No global future helper is
  added.
- **Room-cache write failure is diagnostic and non-retrying until the next
  mutation.** The cache is non-authoritative and the relay will hydrate it; an
  automatic retry loop would add lifecycle cost. The immediate in-memory room
  projection remains visible, the failure is recorded, and the next mutation
  starts a fresh drain.
- **Legacy-room persistence gets one bounded retry.** Unlike ordinary room
  cache, the selected room controls future routing. The manager retries once
  after a short owned timer, then records a diagnostic and leaves the current
  in-memory room active. A later app boot can rediscover it.
- **Channel-close failure is log-only; unexpected reconnect escape is
  log-and-watchdog-recover.** Adoption/disposal never waits or retries a close
  that may belong to a replaced channel. Expected `_connect` failures continue
  to become retry state. If an error escapes that boundary, it is diagnosed and
  the existing watchdog may restart the chain, provided the manager is still
  live.
- **Sync commands and detached writes have separate contracts.** Public command
  methods and explicit lifecycle methods return/await persistence errors.
  Stream/timer handlers submit work through a named `SyncService` detached
  boundary that catches, diagnoses, keeps the serializer alive, and applies a
  convergence/recovery policy.
- **Detached transcript failure is visible but does not invent a transcript
  row.** `SyncService` emits an in-memory `SessionPersistenceDegraded` event,
  logs a privacy-safe diagnostic, and requests authoritative `session_sync`.
  `ChatReady` shows a small retryable persistence banner. A later successful
  transcript write emits `SessionPersistenceRecovered` and clears it. Creating
  a fake row in the failed event store would establish a second truth and is
  rejected.
- **Terminal state converges independently of persistence.** `agent_done`,
  protocol error, cancel, send timeout, disconnect, and session replacement set
  the in-memory turn idle even if their event-store write fails. Non-terminal
  chunk/tool write failures do not falsely idle a still-running turn; they use
  the visible degraded state plus replay recovery.
- **Session activation precedes resend/replay.** Room-change work is serialized
  as `activate → stale check → resend held messages → request/replay sync`.
  Online activation, history replay, and every loop with an async read validate
  `_disposed`, lifecycle generation, and captured `RemoteSessionRef` after each
  async gap.
- **Runtime Hive writes are truly serialized.** `_boxes.runtimeBox().put(...)`
  is awaited inside the write operation. Runtime-write failure is diagnostic
  and retries on the next status/presence update; it does not create a chat
  transcript warning.
- **Peer mutation publication queues retry; it does not pull over a pending
  local mutation.** Transient `MeshPublishFailure`, a second conflict, or an
  unexpected exception leaves one coalesced mutation pending and schedules an
  owned retry. `pullOnDemand` defers while that local publication is pending,
  except for the private conflict-rebase pull. Permanent bad-request,
  forbidden, or too-large outcomes are diagnosed and not retried.
- **The peer hook carries mutation intent.** `PeerMutationKind.upsert/delete`
  lets `MeshSyncService` safely allow an empty publish after a real delete. The
  Settings revoke path returns to normal `deletePeer`, and its duplicate
  fire-and-forget mesh dependency disappears. Pull/apply continues using silent
  storage methods and never republishes.

No operator-only product direction question remains. These choices preserve the
local-first and relay-authoritative contracts while choosing reversible,
owner-local recovery policies.

## Architectural choice

### Considered approaches

1. **Add `catchError` at every call site.** This is the smallest diff, but it
   leaves ordering undefined, duplicates policy, and cannot prevent stale writes
   after session replacement.
2. **Introduce one global safe-unawaited helper.** This removes lint noise but
   erases the distinction between boot recovery, cache persistence, transcript
   convergence, mesh retry, and teardown. It optimizes for syntax rather than
   ownership.
3. **Use owner-local async boundaries with typed diagnostics and generation
   guards.** Router/Chat own startup, `ConnectionManager` owns room cache and
   retry teardown, `SyncService` owns serialized transcript work, and
   `MeshSyncService` owns post-mutation publication.

**Choice: option 3.** It follows existing service/ViewModel boundaries, keeps
failure policy next to the state it can repair, and adds no cross-app execution
abstraction. The only shared addition is a typed privacy-safe diagnostic event,
not a future runner.

**Trickiest unit:** Unit 5, because transcript persistence, live turn state,
session replacement, and reconnect replay must remain ordered without making
stream listeners `async` or creating a second transcript truth.

## Implementation Units

### Unit 1: Typed optional active-room capability (quick win)

**Story:** existing `gate-cruft-dynamic-setactiveroom-fallback`

**Files:**

- `app/lib/data/transport/channel.dart`
- `app/lib/data/transport/connection_manager.dart`
- `app/lib/data/transport/peer_channel.dart`
- `app/lib/data/transport/ws_transport.dart`
- `app/lib/pairing/pair_request_flow.dart`
- `app/test/data/transport/connection_manager_test.dart`
- `app/test/pairing/pair_request_flow_test.dart`

```dart
abstract interface class IActiveRoomTarget {
  void setActiveRoom(String roomId);
}

void _propagateActiveRoom(String roomId, IChannel link) {
  if (link case IActiveRoomTarget target) target.setActiveRoom(roomId);
}
```

`PlainPeerChannel` and `WsTransport` implement the optional capability. Pairing
and connection code test the capability; unsupported test/in-memory transports
remain no-ops.

**Error surface:** none; this is behavior-preserving and removes the blanket
`dynamic` catches.

**Acceptance criteria:**

- [ ] No dynamic `setActiveRoom` call remains in `app/lib/`.
- [ ] Unsupported transports remain silent no-ops.
- [ ] Active-room propagation tests at
      `connection_manager_test.dart:261-297` remain green with an explicitly
      typed recording channel.
- [ ] No wire, timing, or UI behavior changes.

### Unit 2: Normalize best-effort close/retry ownership (quick win)

**Story:** existing `gate-cruft-empty-catch-old-channel-close` (also covers the
structural portions of `gate-cruft-room-adoption-persist-dropped` and
`gate-refactor-lifecycle-connection-retry-floating`)

**Files:**

- `app/lib/data/transport/connection_manager.dart`
- `app/test/data/transport/connection_manager_test.dart`

```dart
void _closeBestEffort(IChannel channel) {
  unawaited(channel.close().catchError((Object _, StackTrace __) {}));
}

unawaited(
  _storage.savePeer(updated).catchError((Object _, StackTrace __) {}),
);

// Expected connect failures are converted to retry state inside _connect.
unawaited(_connect(peer));
```

Remove the redundant `Future(() async { ... })`, no-op `.then`, and local lint
ignores while preserving the exact current silent/non-fatal policy. Unit 4 then
adds the explicitly behavior-changing diagnostics and bounded legacy retry;
implementation may land Units 2 and 4 in one cohesive edit while preserving
their separate acceptance checkpoints.

**Error surface:** none in this quick win. Expected connect failure still becomes
`StatusRetrying`; close and legacy-save failures remain silent until Unit 4.

**Acceptance criteria:**

- [ ] Adoption never waits for old-channel close.
- [ ] Close failure cannot abort adoption or synchronous disposal.
- [ ] Retry timing and attempt accounting are unchanged.
- [ ] The redundant future allocation, no-op `.then`, and cited lint ignores are
      removed.

### Unit 3: Router and Chat startup ownership

**Story:** `feature-app-async-lifecycle-ownership-startup-ownership`

**Files:**

- `app/lib/routing/app_router.dart`
- `app/lib/ui/chat/viewmodels/chat_viewmodel.dart`
- `app/lib/ui/chat/states/chat_state.dart`
- `app/lib/ui/chat/chat_page.dart`
- `app/test/routing/app_router_test.dart` (new)
- `app/test/ui/chat/chat_viewmodel_test.dart`

```dart
enum _BootFailureStage { preferences, identity, storage, connection }

final class _BootFailure {
  const _BootFailure(this.stage, this.message);
  final _BootFailureStage stage;
  final String message;
}

class _BootState extends ChangeNotifier {
  Future<void> load(
    PairingStorage storage,
    ConnectionManager conn,
    Preferences prefs,
    OwnerIdentityBridge ownerBridge,
    MeshSyncService meshSync, {
    void Function()? installWatcherAfterBoot,
  });

  void invalidate();
  _BootFailure? get failure;
  bool get loading;
}

final class ChatInitializationFailed extends ChatState {
  const ChatInitializationFailed(this.message);
  final String message;
}

class ChatViewModel extends ViewModel<ChatState> {
  Future<void> initialize();
  Future<void> _initializeRun(int generation);
  Future<void> _refreshSessionBinding(int generation);
  bool _isCurrentRun(int generation);
}
```

Implementation notes:

- `_BootState.load` sets loading, clears the prior failure, increments a run id,
  and catches each phase separately. It awaits `conn.boot` before setting ready.
- `buildRouter` starts `unawaited(boot.load(...))`; that future is safe because
  `load` never leaks a failure. `/boot` switches from spinner to a concise error
  and Retry button. The redirect checks failure before ready.
- Identity sync-unavailable remains a normal typed branch to
  `/sync-required`; mesh fetch returning `false` remains a local-cache fallback.
  A thrown storage/crypto failure is a boot error.
- `ChatViewModel` constructor uses `unawaited(initialize())`; `initialize`
  catches by phase, invalidates superseded work, and emits
  `ChatInitializationFailed` only for the current run. Retry awaits the same
  method.
- Initial and rooms-stream rebinds share one serialized/generation-guarded path.
  A rebind failure cancels session-scoped message/runtime subscriptions before
  showing failure so old-session rows cannot masquerade as current.
- `dispose` increments the generation before cancelling subscriptions; no
  completion after that point may emit or install a subscription.

**Error surface:** safe phase-specific text on `/boot`; recoverable
`ChatInitializationFailed` with Retry in Chat. Technical details stay out of UI.

**Acceptance criteria:**

- [ ] Router does not leave `/boot` until preferences, identity, peer list,
      cache restore, and the initial `ConnectionManager.boot` attempt settle.
- [ ] Retryable network connect failure routes to Home with `StatusRetrying`;
      preferences/identity/storage/bootstrap exceptions stay on `/boot` with
      Retry.
- [ ] A stale boot run cannot install a watcher or publish ready after retry,
      Owner-key replacement, or disposal.
- [ ] Chat storage, connection switch, and sync activation failures become
      `ChatInitializationFailed` and are retryable.
- [ ] Dispose or a newer initialization prevents every stale completion and
      subscription install.
- [ ] Successful bootstrap behavior and no-peer behavior remain covered.

### Unit 4: Connection persistence and teardown observability

**Story:** `feature-app-async-lifecycle-ownership-connection-persistence`

**Files:**

- `app/lib/data/transport/connection_manager.dart`
- `app/lib/domain/contracts/debug_log.dart`
- `app/test/data/transport/connection_manager_test.dart`
- `app/test/domain/contracts/debug_log_test.dart`
- `app/test/data/debug/debug_capture_routing_test.dart`

```dart
enum DebugTag {
  // existing tags omitted
  lifecycleFailure,
}

enum LifecycleOperation {
  channelClose,
  roomCachePersist,
  legacyRoomPersist,
  retryConnect,
  transcriptWrite,
  runtimeWrite,
  sessionRebind,
  meshPublish,
}

final class LifecycleFailureEvent extends DebugEvent {
  const LifecycleFailureEvent({
    required super.ts,
    required this.operation,
    required this.reason,
    this.peerTail,
    this.room,
    this.sessionIdTail,
    this.retryScheduled = false,
  }) : super(tag: DebugTag.lifecycleFailure);

  final LifecycleOperation operation;
  final String reason;
  final String? peerTail;
  final String? room;
  final String? sessionIdTail;
  final bool retryScheduled;
}

class ConnectionManager extends Service {
  void _scheduleRoomPersistence(String peerKey);
  Future<void> _drainRoomPersistence(String peerKey);
  Future<void> _persistLatestRoomSnapshot(String peerKey, int revision);
  Future<void> _persistLegacyRoomWithRetry(PeerRecord updated);
  void _closeBestEffort(IChannel channel, {required String operation});
}
```

Implementation notes:

- The diagnostic event is the shared typed record required by the existing
  `DebugLog` registry. It is not a shared async executor. Its `reason` is
  clamped, and it carries no body, image, tool args/results, full key, or full
  session id.
- `_scheduleRoomPersistence` increments a revision and starts at most one drain
  per canonical peer key. The drain coalesces bursts. After `listPeers` and
  `loadRooms`, it checks `_disposed` and that its revision is still latest
  before `saveRooms`; otherwise it loops on the newest snapshot.
- An ordinary cache-write failure records `roomCachePersist`, ends that drain,
  and leaves the next mutation eligible to start another. In-memory rooms are
  never rolled back.
- Legacy room persistence records the first failure and schedules one owned
  retry timer. A second failure is recorded with `retryScheduled:false`.
- `dispose` marks disposed before cancelling timers/subscriptions and before
  best-effort close. Pending drains observe the flag and do not begin a final
  write; an already-entered platform write is allowed to complete.
- Retry callbacks check disposed/current peer before connecting. An unexpected
  `_connect` escape records `retryConnect`; the existing watchdog is the
  recovery mechanism rather than a second retry loop.

**Error surface:** typed debug diagnostics. Cache state remains immediately
visible in memory; teardown remains non-blocking; connection status keeps its
existing retry/offline UI.

**Acceptance criteria:**

- [ ] All six room-persistence launch sites use `_scheduleRoomPersistence`.
- [ ] Rapid updates for one peer cannot persist an older snapshot after a newer
      one; different peers do not block one another.
- [ ] A disposed or superseded drain does not start a final storage write.
- [ ] One failed cache write is diagnosed, does not roll back UI, and a later
      mutation retries.
- [ ] Legacy-room save retries once, then diagnoses final failure.
- [ ] Close failure is diagnosed without blocking adoption/disposal; unexpected
      reconnect escape is diagnosed without bypassing lifecycle guards.
- [ ] The debug registry's exhaustive variant/privacy tests cover the new event.

### Unit 5: Sync write, rebind, transcript failure, and convergence semantics

**Story:** `feature-app-async-lifecycle-ownership-sync-failure-semantics`

**Files:**

- `app/lib/data/sync/sync_service.dart`
- `app/lib/data/sync/sync_events.dart`
- `app/lib/domain/contracts/debug_log.dart`
- `app/lib/ui/chat/viewmodels/chat_viewmodel.dart`
- `app/lib/ui/chat/states/chat_state.dart`
- `app/lib/ui/chat/chat_page.dart`
- `app/test/data/sync/sync_service_test.dart`
- `app/test/data/sync/session_history_replay_test.dart`
- `app/test/ui/chat/chat_viewmodel_test.dart`

```dart
final class SessionPersistenceDegraded extends SessionEvent {
  const SessionPersistenceDegraded(this.message);
  final String message;
}

final class SessionPersistenceRecovered extends SessionEvent {
  const SessionPersistenceRecovered();
}

class SyncService extends Service {
  Future<void> _enqueue(Future<void> Function() operation);

  void _runDetachedWrite({
    required LifecycleOperation operation,
    required Future<void> Function() write,
    RemoteSessionRef? expectedRef,
    bool requestReplayOnFailure = false,
  });

  Future<void> _handleRoomsChanged();
  Future<void> _onlineActivated();
  bool _isCurrentLifecycle(int generation, [RemoteSessionRef? ref]);
}

final class ChatReady extends ChatState {
  const ChatReady({
    required this.messages,
    // existing fields omitted
    this.persistenceWarning,
  });
  final String? persistenceWarning;
}
```

Implementation notes:

- `_enqueue` still returns the real operation future so awaited callers observe
  failure. It stores an error-absorbing continuation only as the predecessor for
  the next queued operation, ensuring one failure cannot poison later writes.
- `_runDetachedWrite` is private to `SyncService`. It owns stream/timer work,
  records `LifecycleFailureEvent`, emits degradation once, and optionally calls
  `requestSync`. A successful transcript operation clears the degraded latch and
  emits recovery.
- Replace each transcript lint suppression with the named detached boundary.
  Preserve event ordering by batching logically terminal pairs (`Cancelled`,
  protocol error) through `_appendTranscriptEvents` as today.
- Terminal handlers set/retain idle independently of persistence completion.
  `_failPendingSend` uses `try/finally` so stream and turn state settle even if
  the failure row cannot be stored.
- `_onRoomsChanged` queues one owned lifecycle operation: resolve ref, await
  `activate` when changed, validate generation/ref, then resend held messages,
  then request sync. It must not start activation and resend as sibling futures.
- `_onlineActivated`, `_resendHeldPendingMessages`, `_replayHistory`, and loops
  over event-store results re-check disposed/generation/ref after every await.
- `dispose` sets `_disposed` and increments generation before closing streams.
  Queued storage operations may finish I/O but cannot publish state for the
  replacement/disposed session.
- Await `runtimeBox().put` inside the queued closure. Runtime failure logs only;
  the next connection/presence event retries it.
- `ChatViewModel` maps persistence degraded/recovered events into
  `ChatReady.persistenceWarning`; `ChatPage` reuses its existing banner style
  with a Retry Sync action. It preserves transcript rows and disables no command
  solely because the cache is degraded.

**Error surface:** transcript degradation is both a typed debug event and a
visible, retryable chat banner. No fake transcript row is created. Runtime-only
failure is debug-only. Terminal turn state remains idle where required.

**Acceptance criteria:**

- [ ] No `discarded_futures` suppression remains in `SyncService` for the cited
      paths; every detached operation names an owner policy.
- [ ] Awaited command/lifecycle callers receive write failures, while later
      queued operations still execute after one failure.
- [ ] Runtime Hive `put` is part of queue completion.
- [ ] Activation completes before held-message resend and replay for the new
      session.
- [ ] Old-session work cannot append, emit recovery/degradation, install state,
      or send after an async gap.
- [ ] Injected transcript-store failure emits one visible degraded signal,
      requests replay, and a subsequent successful write clears the warning.
- [ ] Injected failure on a terminal event still leaves `working:false`; an
      injected non-terminal write failure does not falsely idle an active turn.
- [ ] Existing convergence coverage at `sync_service_test.dart:1988-2070`
      remains green and is extended with failing-adapter/Hive cases.

### Unit 6: Mesh mutation publication ownership

**Story:** `feature-app-async-lifecycle-ownership-mesh-publication`

**Files:**

- `app/lib/pairing/storage.dart`
- `app/lib/data/mesh/mesh_sync_service.dart`
- `app/lib/config/dependencies.dart`
- `app/lib/ui/settings/viewmodels/settings_viewmodel.dart`
- `app/lib/domain/contracts/debug_log.dart`
- `app/test/pairing/storage_test.dart`
- `app/test/data/mesh/mesh_sync_service_test.dart`
- `app/test/ui/settings/settings_viewmodel_test.dart`

```dart
enum PeerMutationKind { upsert, delete }
typedef PeerMutationHook = void Function(PeerMutationKind kind);

class PairingStorage extends ChangeNotifier {
  void attachPeerMutationHook(PeerMutationHook? hook);
}

class MeshSyncService extends ChangeNotifier {
  void publishAfterPeerMutation(PeerMutationKind kind);
  Future<void> _drainPendingMutationPublish();
  void _scheduleMutationPublishRetry();
}
```

Implementation notes:

- `savePeer` emits `upsert`; `deletePeer` emits `delete`; silent methods remain
  hook-free. DI attaches `meshSync.publishAfterPeerMutation` directly.
- The boundary marks a local mutation pending and starts at most one drain. A
  mutation arriving during publish coalesces into one more snapshot publish,
  so `_publishing` no longer turns a real mutation into an ignored
  `already in flight` result.
- Delete permits empty membership because only explicit local deletion reaches
  this hook; pull/apply remains silent. Settings returns to `deletePeer` and
  removes its optional `MeshSyncService` dependency and explicit discarded
  publish.
- `MeshPublishOk` clears the pending snapshot if no newer mutation arrived.
  Conflict uses the existing private pull/rebase/retry. A final conflict and
  `MeshPublishFailure` keep pending and schedule the owned coalesced retry.
  Bad-request/forbidden/too-large are permanent: diagnose, clear the retry, and
  do not spin.
- `pullOnDemand` first drains or defers behind pending local publication so a
  failed publish cannot be overwritten by a normal pull. The conflict-rebase
  path uses a private pull that is allowed during publication.
- Unexpected exceptions are caught at this boundary, diagnosed as
  `meshPublish`, and treated as transient. Retry timer, drain, and notification
  all check `_disposed`; `dispose` cancels the timer.

**Error surface:** typed privacy-safe diagnostics. Local peer mutation remains
immediate/non-blocking. Transient publication recovers in the background;
permanent typed failures do not loop.

**Acceptance criteria:**

- [ ] The DI hook delegates to `publishAfterPeerMutation` with no discarded
      future.
- [ ] Every `MeshPublishResult` variant has an explicit disposition.
- [ ] A mutation during publish causes one follow-up publish rather than an
      ignored `already in flight` result.
- [ ] Transient/exception failure queues one coalesced retry; permanent typed
      failure logs and does not retry.
- [ ] Normal pulls cannot overwrite a pending local mutation; conflict rebase
      still works.
- [ ] Last-peer revoke publishes `members=[]` through mutation intent and no
      longer performs a duplicate explicit publish from Settings.
- [ ] Pull/apply silent writes do not re-enter publication; dispose cancels
      retry/drain publication state.

## Implementation Order

1. `gate-cruft-dynamic-setactiveroom-fallback` — typed active-room capability.
2. `gate-cruft-empty-catch-old-channel-close` — local best-effort cleanup
   (land cohesively with Unit 4 diagnostics if preferable).
3. `feature-app-async-lifecycle-ownership-startup-ownership` — router and Chat
   startup ownership.
4. `feature-app-async-lifecycle-ownership-connection-persistence` — per-peer
   cache drain plus shared typed lifecycle diagnostic.
5. `feature-app-async-lifecycle-ownership-sync-failure-semantics` — ordered
   rebind/write/replay and visible degradation.
6. `feature-app-async-lifecycle-ownership-mesh-publication` — typed mutation
   hook and queued publication retry.
7. Close the remaining gate findings as provenance checkpoints when their
   mapped unit's acceptance evidence is green.

The behavior-story dependency graph is:

- startup ownership: `depends_on: []`
- connection persistence: `depends_on: [startup ownership]`
- sync failure semantics: `depends_on: [connection persistence]`
- mesh publication: `depends_on: [connection persistence]`

This ordering also avoids concurrent edits to the shared `DebugEvent` registry.
The parent feature remains the normal single-worker implementation/review bundle;
stories are checkpoints, not parallel agent assignments.

Cycle validation note: `.work/bin/work-view --blocking` was attempted for all
four new stories but the repository-wide scan is currently blocked by unrelated
pre-existing malformed frontmatter in
`.work/archive/story-document-deferred-relay-volume-cutover.md` and duplicate
`updated` fields in two retained `v0.1.0` release stories. A direct inbound-id
scan found no pre-existing reference to any new story; the declared graph above
is acyclic (`startup → connection → {sync, mesh}`).

## Simplification

- Remove three dynamic room-targeting catches, redundant `Future` allocation,
  no-op `.then`, and cited lint suppressions.
- Keep `SyncService` intact; splitting it is a separate architectural effort and
  would obscure this failure-semantics change.
- Do not add a global `safeUnawaited`/future extension. Each owner retains its
  policy.
- Consolidate Settings revoke publication into the canonical peer-mutation hook,
  removing its optional mesh dependency and duplicate publish path.
- Keep `PairingStorage` synchronous/local-first and network-independent; it emits
  mutation intent only.

## Mockups

No mockup is required. `/boot` failure, Chat initialization failure, and the
persistence warning are minor compositions that reuse the existing `_EmptyState`,
Retry action, and banner visual patterns; there is no new screen or journey.

## Testing

Smallest useful surface:

- **Router interface tests** (`app/test/routing/app_router_test.dart`): deferred
  fakes prove routing waits for boot, retryable network state reaches Home, each
  thrown phase remains on `/boot`, Retry starts a new generation, and stale runs
  cannot publish ready.
- **Chat regression tests** (`chat_viewmodel_test.dart`): failing storage and
  failing `SyncService.activate`, dispose during each await, retry success, and
  room rebind failure cannot retain old-session rows.
- **Connection boundary tests** (`connection_manager_test.dart`): controlled
  storage completers prove latest-wins per-peer ordering; a failing adapter
  proves next-mutation retry; close/legacy/retry failures produce the typed
  diagnostic and obey bounded policy.
- **Sync failing-adapter tests** (`sync_service_test.dart`): inject a
  `TranscriptEventStore` that fails one append/read and then recovers; assert
  the queue continues, degraded/recovered events occur once, replay is requested,
  terminal failure converges idle, and stale-session work cannot publish after
  release of a completer. Use a controlled Hive failure for runtime `put` to
  prove it is awaited and diagnosed.
- **Preserve existing convergence tests** at
  `sync_service_test.dart:1988-2070`; extend them rather than replacing their
  success/error/cancel/compaction evidence.
- **Mesh interface tests** (`mesh_sync_service_test.dart` and
  `storage_test.dart`): mutation kind delivery, in-flight coalescing, transient
  retry, permanent no-retry, last-peer empty publication, pull deferral, silent
  apply non-reentrancy, and disposal cancellation.
- **Debug contract tests**: add the new diagnostic to the exhaustive sealed
  switch, field allow-list, value clamp, and capture-site registry.

No test should assert private scheduling mechanics when an externally visible
boundary (ordered storage calls, emitted state/event, result disposition) is
available. No existing useful test is slated for removal.

## Risks

- **Riskiest assumption:** authoritative replay remains available after local
  transcript persistence recovers. If the Pi/session is gone, the visible
  degraded banner must remain rather than pretending recovery succeeded.
- **Failure condition:** a terminal handler still couples idle transition to a
  successful store append, leaving a stuck working projection under injected
  failure. The implementation must set idle outside/inside `finally` and prove
  it with the failing store.
- **Failure condition:** a pending local mesh mutation is pulled over before its
  retry, resurrecting a deleted peer. Pull deferral plus the private conflict
  rebase path is mandatory.
- **Failure condition:** generation checks occur only at method entry. Every
  async gap that precedes state mutation, subscription install, send, or final
  persistence must revalidate.
- **Fallback if the ordered Sync lifecycle boundary proves too entangled:** land
  transcript detached-write diagnostics/convergence first, retain the current
  rebind triggers behind one generation guard, and split activation-before-
  resend into a follow-up without introducing parallel async callbacks.
- **Fallback if mesh retry coordination is unsafe:** keep the owned result
  inspection and diagnostics, disable automatic pulls while dirty, and retry
  only on foreground resume/local mutation. Do not revert to dropped publish
  futures.
- **Least certain area:** platform secure-storage writes already entered before
  disposal cannot be cancelled. The guarantee is therefore “do not begin a
  final write after invalidation,” not cancellation of an in-flight plugin call.

## Verification

Run from `app/`:

```bash
flutter analyze
flutter test
flutter build apk --debug
```

The build smoke may be skipped only for an explicit environment/resource reason;
analyze and the full test suite remain required.

## Implementation

Completed all six units and closed all eleven originating gate findings.

- Added typed active-room capability and owned channel teardown diagnostics.
- Made router and Chat startup awaited, retryable, serialized, and generation
  guarded.
- Added per-peer latest-wins room persistence, bounded legacy-room retry, and
  lifecycle-safe reconnect handling.
- Made Sync writes/rebind/replay ordered and observable, including transcript
  degradation/recovery UI and terminal idle convergence under failed writes.
- Added typed peer mutation intent plus a coalescing, retrying mesh publication
  drain; normal pulls defer behind dirty local membership, and Settings no
  longer owns a duplicate mesh future.
- Hardened the newly exercised Sync lifecycle tests to wait for observable
  projections instead of assuming a fixed scheduler delay. The default parallel
  Flutter runner still exposed unrelated fixed-delay sensitivity at rotating
  legacy assertions, so the authoritative complete run used one test worker.

Integrated review found no remaining material blocker in the implemented
surfaces. No protocol or persistence schema changed, and no generated artifact
is committed.

Verification from `app/`:

- `flutter analyze lib test` — passed with no issues.
- Focused router, Chat, connection, debug-contract, Sync/replay, pairing storage,
  mesh, and Settings suites — passed.
- `flutter test --concurrency=1` — 732 tests passed.
- `flutter build apk --debug` — passed; generated
  `build/app/outputs/flutter-apk/app-debug.apk` after redirecting read-only
  Gradle/Android/Kotlin runtime directories to disposable writable paths.

Implementation discrepancies: no product-design fallback was needed. The only
verification adjustment was serializing the complete Flutter suite because its
legacy fixed-delay tests are scheduler-sensitive under the default parallel
runner; focused suites and the complete serial run are green.

## Review findings (fresh-context review, gpt-5.6-sol, standard weight)

Review verdict: `needs fixes`. Six receiver-confirmed current-cycle findings
(all verified by the orchestrator against current code). These must be fixed
before this feature closes.

### Blocker 1 — stale `sendMessage` can mutate/send into a replaced session
`app/lib/data/sync/sync_service.dart:339-408`. After awaiting
`_appendTranscriptEvent()` at :339, the method does not revalidate
disposal/lifecycle generation/captured ref/channel identity before
`_setTurnActive()` :352, `_armSendTimeout()` :364, `_emitStreaming()` :395,
and `ch.send()` :408. A session rotation during persistence can arm a timer
for the new session and send the old message through a replaced channel.
**Fix:** capture generation/ref, revalidate after the append, reacquire/revalidate
the active channel + room liveness immediately before sending; add a
completer-gated rotation/disposal regression test.

### Blocker 2 — terminal idle can be reopened by an older queued non-terminal projection
`app/lib/data/sync/sync_service.dart:844-912, 1372-1388`. `AgentDone` queues
its terminal append and immediately sets idle at :912. An earlier blocked
`AgentChunk` append can subsequently complete and execute
`_setTurnView(projection.turn)` at :1388, restoring streaming/working. If the
queued terminal append then fails, the turn remains working despite the
terminal event. Error/cancel/compaction have the same queue-order hazard.
**Fix:** introduce a turn/projection epoch or otherwise prevent pre-terminal
writes from publishing turn state after a terminal transition. Add a
deterministic test: block a non-terminal append, deliver a terminal event,
release the old append, then fail the terminal append and still assert idle.

### Blocker 3 — normal mesh pulls can overwrite mutations that become pending during fetch; conflict rebase also loses intent
`app/lib/data/mesh/mesh_sync_service.dart:87-103, 124-172, 279-286`. Pull
deferral is checked only before the request. After `_client.fetch()` at :88,
`_mutationPending` is not rechecked before `_applyVerified()` at :99 or during
its storage awaits. A mutation committed while fetch/apply is in flight can be
overwritten by the relay snapshot. The private conflict pull has the deeper
version of this problem: it applies the relay snapshot and retains only
`PeerMutationKind`, so a deletion/update can be erased before the retry
snapshots storage.
**Fix:** generation-guard normal pull application across every async gap. For
conflict rebase, retain and reapply/merge the actual local mutation or a
protected local snapshot before retrying. Test both a gated normal fetch
followed by mutation and a last-peer deletion receiving a conflict.

### Material 4 — additional Sync stale-completion guards omit disposal/generation
`app/lib/data/sync/sync_service.dart:231, 495-520, 1831-1886`. `_isStillActive()`
checks only `_activeRef`. `_failPendingSend()` can resume after its await at
:506 and mutate streaming/turn state at :519-520 after disposal. `_updateIndex`
and `_writeRuntime` queued closures check only ref equality or peer/room before
beginning `put`; they can start writes after disposal or lifecycle invalidation.
**Fix:** use captured generation plus `_isCurrentLifecycle(generation, ref)`
after `_failPendingSend`'s await and immediately before every queued `put`.

### Material 5 — router boot lifecycle has no production teardown, and Owner-reset continuation is unguarded
`app/lib/routing/app_router.dart:236, 256-269`; `app/lib/main.dart:78-81`. The
locally created `BootState` has no production owner calling `dispose()`; only
tests do. The Owner-reset callback awaits `conn.disconnect()` at :259 then
resets the mesh watermark/starts another boot without validating this reset run
is still current. Overlapping reset/disposal can resume stale work.
**Fix:** give router boot state an explicit app-owned teardown path and
generation-guard the reset continuation after `disconnect`. Set
`watcherInstalled` only after `startWatching` succeeds so Retry can recover a
synchronous watcher-install failure.

### Material 6 — scheduler "hardening" weakened two timeout assertions
`app/test/data/sync/sync_service_test.dart:3070-3101, 3108-3142`. Tests (b) and
(c) changed `pendingSendTimeout` from 60ms to 5s while still waiting only 140ms.
Test (b) no longer waits past the timeout, so it cannot prove a
removed-but-not-cancelled timer won't fire. Test (c) no longer waits past the
original timeout, so it cannot prove `delivery_pending` replaced/extended that
timer.
**Fix:** restore proof of those guarantees using an injected/fake timer or waits
that cross the configured original deadline with deterministic completion
polling.

### Review invariant summary
- Generation guards at every async-gap-before-mutation/send/persistence: FAIL
  (findings 1, 3, 4, 5)
- Terminal convergence independent of persistence: FAIL (finding 2)
- Latest-wins per-peer persistence: PASS
- Mesh coalescing + permanent-no-retry individually PASS; overall mesh safety
  FAILS (pull deferral/rebase racy — finding 3)
- Boot readiness: FAIL overall (teardown/reset — finding 5)
- No BuildContext-after-await-without-mounted in changed UI: PASS
- Test-integrity: MIXED — good hardening overall (Completer gates, _waitUntil
  polling, convergence preserved), but finding 6 materially weakened two
  timer-policy proofs.

## Corrective follow-up

All six fresh-context review findings were corrected without changing the
feature stage.

1. `sendMessage` now captures lifecycle generation, session ref, and channel
   identity before persistence; it revalidates after the append and reacquires
   and checks channel/room liveness immediately before send. Completer-gated
   channel-replacement and disposal tests prove stale completion cannot arm a
   timer, publish working state, or send.
2. Turn projections now carry a monotonic epoch. Every asynchronous projection
   publisher checks the captured epoch, while terminal transitions advance it,
   so a pre-terminal chunk cannot reopen working/streaming after terminal idle.
   The regression blocks the chunk append, delivers `AgentDone`, releases the
   chunk, fails the terminal append, and still observes idle.
3. Mesh pulls capture mutation revision and Owner identity and revalidate them
   after fetch, verification, and every storage await. Conflict handling
   protects the local peer snapshot, applies the verified relay version,
   restores the protected mutation, and only then retries. Gated-fetch and
   last-peer conflict tests prove a new peer and an empty deletion cannot be
   overwritten/resurrected.
4. Pending-send failure convergence captures generation and revalidates after
   transcript persistence. Queued session-index/runtime writes capture the same
   lifecycle and check it immediately before each `put`; disposed/replaced work
   cannot begin a final persistence mutation.
5. `AppRouterOwner` now explicitly disposes the router boot state before DI
   teardown. Owner reset captures an invalidation token and checks it after
   `disconnect`; watcher installation is marked complete only after
   `startWatching` succeeds. Tests cover synchronous install retry and disposal
   during blocked disconnect.
6. Timeout tests (b) and (c) again use the original 60 ms send deadline and
   deterministic deadline polling. They respectively prove a cancelled timer
   stays inert after its deadline and `delivery_pending` replaces it with the
   extended timer.

Verification from `app/`:

- `flutter analyze lib test` — passed with no issues.
- `flutter test --no-pub --concurrency=1 test/data/sync/sync_service_test.dart test/data/mesh/mesh_sync_service_test.dart test/routing/app_router_test.dart` — 119 tests passed.
- `flutter test --concurrency=1` — 739 tests passed.
