---
id: feature-fresh-session-shutdown-and-recoverable-delivery
kind: feature
stage: implementing
tags: [pi-extension, app, lifecycle]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-25
updated: 2026-08-26
---

# Fresh-session shutdown + recoverable-delivery contract

## Brief

Formed by groom (2026-08-25) from two backlog items that name each other:
`backlog-new-session-teardown-session-shutdown` (extension: the fresh-session
handshake should await normal lifecycle/resource drains instead of a
fixed-delay exit) and `backlog-recoverable-delivery-resend-contract`
(app+extension: quiesce → no SDK delivery during teardown → reconnect →
recovery proof; "Pairs with" the former).

One coherent capability: `/new` (mobile-initiated fresh session) must shut
down cleanly under load — draining in-flight delivery, releasing rooms and
locks deterministically — and any message the owner sends across the
boundary must be resend-recoverable, never lost. Evidence anchors: the
2026-08-23 restart-wrapper incident (marker + /quit with no wrapper) and
the swallow-fix lineage (6d1cbad6) both touch this boundary.

## Source items (absorbed — full bodies in git history + archive)

- backlog-new-session-teardown-session-shutdown
- backlog-recoverable-delivery-resend-contract

## Design decisions

- **Delivery guarantee**: use durable app-owned at-least-once recovery for
  unconfirmed `user_message` submissions, retaining the original client id.
  Same-session duplicates collapse through the extension's existing durable
  ingress idempotency; after a deliberate session rotation, an unconfirmed
  submission follows the owner into the successor session. This prioritizes
  the brief's no-loss requirement over impossible exactly-once claims at a hard
  process-crash boundary.
- **Quiescing signal**: add schema-known error code `delivery_retry` for a
  prompt that did not cross into the Pi SDK because a restart fence owns the
  process. Keep `delivery_pending` unchanged for the separate case where the
  live extension itself retained the prompt for local replay.
- **Shutdown mechanism**: keep the established process-manager result
  `EXIT_FRESH_SESSION = 42`, but produce it only after invoking and awaiting the
  active runtime's normal `reason: new` disposal path. The fixed 100 ms exit is
  not a delivery boundary and is removed.
- **Bounded failure posture**: normal shutdown awaits accepted ingress, secure
  owner-channel sequence persistence/enqueue, relay close, mesh close, and lock
  release. A bounded liveness deadline may still force process termination;
  that path is explicitly uncertain delivery and relies on the app outbox, not
  on elapsed time as proof.
- **Trust and routing boundary**: the relay stays unchanged and sees only its
  existing opaque owner-channel ciphertext. This is an app ↔ extension paired
  behavior change and must be documented in `AGENTS.md`; old endpoints may
  parse the additive open error code but do not provide the complete guarantee.
- **Action recovery**: the `session_new` action stages its correlated
  `action_ok` before channel drain. If that final ACK is lost after local
  enqueue, canonical room/session rotation remains the authoritative proof of
  the new session; the command is not blindly resent and cannot create two
  fresh sessions.
- **Scope discipline**: reuse the existing pending/failed bubble and room
  hydration surfaces. No new UI, relay queue, generic exactly-once framework,
  or cross-PC delivery behavior is introduced.
- **Design dispatch**: direct-read mapping across the schema, lifecycle
  composition, secure owner channel, app SyncService, durable transcript
  storage, and production-backed e2e harness. The delegated worker context had
  no nested generic-subagent adapter, so the otherwise-warranted design-time
  fresh-context advisory pass was non-blockingly degraded; implementation
  review remains `standard` (one independent pass, source: caller/default).

## Mockups

No UI surface. The feature reuses current pending/failed message bubbles and
canonical reconnect/session hydration; no parent epic or mock inheritance
applies.

## Architectural choice

### Option A — lifecycle drain plus durable mobile outbox (chosen)

Fence new owner prompts synchronously, finish already-accepted deliveries,
stage the action/reset frames, and call the same runtime disposal used by
`session_shutdown`. Independently, persist every unconfirmed mobile prompt in
an encrypted room-scoped outbox and replay it by stable id only after an
authoritative live-room/session snapshot. This preserves the existing
endpoint-owned E2E boundary, survives app and extension restarts, and requires
no relay state.

### Option B — extension-only replay queue

Extend `_pendingDeliveryQueue` and let the outgoing process promise future
replay. This minimizes app work but cannot survive the exact wrapper/daemon
process exit the feature exists to make safe. It also makes
`delivery_pending` dishonest once the process has committed to termination.
Rejected because the receiver cannot own recovery after it exits.

### Option C — relay ACK/offline queue

Have the relay retain ciphertext until app and extension ACK end-to-end
receipt. This could centralize transport retries, but it changes the relay from
stateless message routing into a durable queue, complicates AEAD replay
semantics, and expands a component that does not understand owner payloads.
Rejected because it contradicts `docs/DECISIONS.md`, the self-hostable relay
posture, and the caller's relay-untouched constraint.

The chosen design makes the app's encrypted outbox the durable delivery
authority and the extension lifecycle coordinator the shutdown authority.
Neither duplicates the other's responsibility.

## Trickiest unit first

The hardest unit is **cross-session mobile resend**, not process exit. The app
must distinguish a message that is merely awaiting an echo from one confirmed
in a different session, survive process death, avoid resending before room
liveness is authoritative, and not let a late old-session echo erase a retry
already targeted at the successor. The outbox therefore stores a target
session and uses compare-by-target confirmation; retargeting is durable before
a successor send.

## Implementation units

### Unit 1: Schema-owned recoverable-delivery signal

**Files**:
- `protocol/schema/defs/app-pi-common.schema.json`
- `protocol/fixtures/app-pi/server-messages.jsonl`
- `tools/protocol-codegen/fixtures/app_pi_client_dart_ir.json`
- generated `pi-extension/src/protocol/generated/protocol.generated.ts`
- generated `app/lib/protocol/generated/protocol.g.dart`
- `PROTOCOL.md`, `docs/SPEC.md`, `docs/ARCHITECTURE.md`, `AGENTS.md`

**Story**: `feature-fresh-session-shutdown-and-recoverable-delivery-retry-contract`

```ts
// Generated from the canonical schema; do not hand-maintain a second enum.
export type KnownErrorCode =
  | /* existing codes */
  | "delivery_pending"
  | "delivery_retry";

// Existing ErrorMessage shape is reused.
type DeliveryRetry = Extract<ServerMessage, { type: "error" }> & {
  code: "delivery_retry";
  in_reply_to: string;
  session_id: string;
};
```

**Implementation notes**:
- `delivery_retry` means the receiver did not hand this id to the SDK and the
  sender owns retry after fresh authoritative reachability.
- The error carries no prompt text and requires no relay parsing.
- Update the maintained Dart generator IR in the same stride as the canonical
  schema, then regenerate; generated projections are never hand-edited.
- Foundation updates are code-first and replace any claim that only held-before-
  send messages are reconnect-retryable.

**Acceptance criteria**:
- [ ] TypeScript and Dart decode the fixture and expose the same known code.
- [ ] Unknown error strings remain accepted; this addition does not close the
      forward-compatible error union.
- [ ] Durable docs state the paired app/extension guarantee without claiming a
      relay queue or exactly-once delivery.

---

### Unit 2: Managed fresh-session shutdown coordinator

**Files**:
- `pi-extension/src/extension/fresh_session_shutdown.ts` (new)
- `pi-extension/src/extension/ports.ts`
- `pi-extension/src/extension/composition_root.ts`
- `pi-extension/src/index.ts`
- matching focused tests

**Story**: `feature-fresh-session-shutdown-and-recoverable-delivery-managed-shutdown-drain`

```ts
export type OwnerDeliveryFenceReason = "hot_reload" | "fresh_session";
export type FreshSessionShutdownResult =
  | { status: "unavailable" }
  | { status: "already_quiescing" }
  | { status: "stale_runtime" }
  | { status: "exiting"; drain: "complete" | "deadline_exceeded" };

export interface FreshSessionShutdownRequest {
  stageAcknowledgementAndReset(): void;
  shutdownRuntime(reason: "new"): Promise<boolean>;
}

export class FreshSessionShutdownCoordinator {
  constructor(deps: {
    isRestartManaged(): boolean;
    drainAcceptedDeliveries(): Promise<void>;
    terminate(exitCode: number): void;
    shutdownDeadlineMs: number;
  });

  get fenceReason(): OwnerDeliveryFenceReason | null;
  beginHotReloadFence(): boolean;
  request(input: FreshSessionShutdownRequest): Promise<FreshSessionShutdownResult>;
}

export interface OutpostPiRuntime {
  readonly epoch: RuntimeEpoch;
  readonly ports: OutpostPiRuntimePorts;
  readonly lease: FactoryLease;
  register(): void;
  registerLifecycle(): void;
  isOwner(): boolean;
  dispose(reason?: SessionLifecycleReason): Promise<boolean>;
}
```

**Implementation notes**:
- `request()` changes the fence synchronously before its first `await`.
  `_routeClientMessageFrom` checks the fence before `_disposed`; a fenced
  `user_message` gets `delivery_retry` and never reaches `_wakeAgent`.
- Drain `_inflightUserDeliveries` to a stable empty snapshot. No new attempt can
  enter after the fence.
- `stageAcknowledgementAndReset()` sends correlated `action_ok`, calls the
  existing `_resetSessionForNew(id)`, and is invoked once.
- Bind the active runtime's epoch-scoped `dispose("new")` capability when the
  command surface registers. A stale lease returns `false`; it never exits the
  current process.
- `disposeRuntimePorts` attempts mesh/cwd-lock closure even when relay stop
  rejects. The shutdown deadline is a liveness escape, not a sleep-based flush.
- Owner detach/`whenIdle()` remains the local boundary: accepted frames finish
  sequence persistence and synchronous relay enqueue before relay close. There
  is deliberately no false relay-to-app ACK claim.
- Hot reload adopts the same fence/error producer, replacing its ad hoc
  `_hotReloading` delivery-error branch; its marker + graceful SIGTERM process
  contract otherwise remains unchanged.

**Acceptance criteria**:
- [ ] A prompt accepted before the fence settles before reset; a prompt after
      the fence gets `delivery_retry` and produces zero SDK calls.
- [ ] `action_ok` and empty history are accepted into the protected outbound
      tail before owner detach; exit 42 waits for the drain and lock-release
      attempts.
- [ ] Concurrent fresh requests do not reset or exit twice.
- [ ] The direct SDK `newSession({withSession})` path and unmanaged structured
      error stay unchanged.
- [ ] The fixed 100 ms process-exit timer is gone.

---

### Unit 3: Encrypted app owner-delivery outbox

**Files**:
- `app/lib/domain/entities/pending_owner_delivery.dart` (new)
- `app/lib/domain/contracts/owner_delivery_outbox.dart` (new) and barrel
- `app/lib/data/local/records/pending_owner_delivery_record.dart` (new)
- `app/lib/data/local/hive_owner_delivery_outbox.dart` (new)
- `app/lib/data/local/boxes.dart`
- `app/lib/config/dependencies.dart`
- `app/lib/data/sync/sync_service.dart`
- adapter and SyncService tests

**Story**: `feature-fresh-session-shutdown-and-recoverable-delivery-durable-mobile-resend`

```dart
final class PendingOwnerDelivery {
  const PendingOwnerDelivery({
    required this.id,
    required this.peerEpk,
    required this.roomId,
    required this.targetSessionId,
    required this.text,
    required this.createdAt,
    this.image,
    this.streamingBehavior,
  });

  final String id;
  final String peerEpk;
  final String roomId;
  final String? targetSessionId;
  final String text;
  final DateTime createdAt;
  final MessageImage? image;
  final UserMessageStreamingBehavior? streamingBehavior;

  PendingOwnerDelivery target(String sessionId);
}

abstract interface class OwnerDeliveryOutbox {
  Future<void> upsert(PendingOwnerDelivery delivery);
  Future<List<PendingOwnerDelivery>> listForRoom({
    required String peerEpk,
    required String roomId,
  });
  Future<void> removeConfirmed({
    required String id,
    required String confirmedSessionId,
  });
}
```

**Implementation notes**:
- Add one common encrypted Hive box, included in owner-transition and explicit
  transcript-discard recovery. Key entries by peer/room/client id; reject
  malformed records at the adapter boundary.
- `sendMessage` writes the optimistic transcript fact, then outbox intent,
  then the channel. If outbox persistence fails, do not send; fail visibly
  rather than creating an untracked ambiguous delivery.
- On fresh live-room confirmation, `_recoverPendingOwnerDeliveries` lists the
  room's entries, durably retargets stale/null targets to the current canonical
  session, appends an idempotent submitted fact to that session, and resends the
  original id. One lifecycle-generation in-flight set prevents re-entrant room
  snapshots from duplicating sends.
- Keep each entry through send and timeout. Delete only after a matching-target
  live `user_input`/`user_message` echo or equivalent `session_history`
  confirmation is durably appended. A late old-session confirmation cannot
  delete a successor-targeted entry.
- `delivery_retry` cancels the short echo backstop and leaves the bubble/outbox
  recoverable. Permanent receiver errors remove the entry and append the normal
  visible failure.
- Retire `_resentHeldPendingIds` and `_resendHeldPendingMessages`; transcript
  `held` remains provenance/UI state, not a second queue.

**Acceptance criteria**:
- [ ] Offline, half-open, quiesce-rejected, and sent-but-unconfirmed prompts all
      survive app service/process reconstruction in encrypted storage.
- [ ] No retry occurs until both canonical session identity and current room
      liveness are authoritative.
- [ ] Same-session reconnect and session rotation reuse the original id and send
      once per recovery generation.
- [ ] Matching live or replay confirmation removes the outbox entry; stale
      confirmation, failed resend, or storage error cannot erase it silently.
- [ ] Existing pending/failed UI semantics remain and no new screen is needed.

---

### Unit 4: Production-backed quiesce/reconnect proof

**Files**:
- `pi-extension/test/support/e2e_pi_host_runtime.ts`
- `pi-extension/test/support/e2e_pi_host_server.ts`
- `app/test/e2e/support/pi_host_client.dart`
- `app/test/e2e/fresh_session_recoverable_delivery_e2e_test.dart` (new)

**Story**: `feature-fresh-session-shutdown-and-recoverable-delivery-boundary-e2e-proof`

```dart
Future<PiHostDeliveryControlStatus> beginDeliveryQuiesce();
Future<PiHostDeliveryControlStatus> deliveryControlStatus();

final class PiHostDeliveryControlStatus {
  const PiHostDeliveryControlStatus({
    required this.fenced,
    required this.sdkDeliveryCount,
  });
  final bool fenced;
  final int sdkDeliveryCount;
}
```

**Implementation notes**:
- The narrow host seam may toggle the production fence and expose a delivery
  count; it may not inject a server message into SyncService.
- Pair and seal normally, send through `SyncService`, carry `delivery_retry`
  through the real generated codec/secure channel/relay, restart the host with
  state preservation, and wait for canonical room reappearance.
- Assert by stable client id and structural counters; never log prompt bodies,
  keys, nonces, or ciphertext.

**Acceptance criteria**:
- [ ] Quiesced submission reaches the app outbox but not the SDK.
- [ ] Reconnect hydration triggers one stable-id resend and confirmation.
- [ ] Final transcript and SDK counter prove one recovered delivery.
- [ ] `e2e/run-pairing.sh` covers the scenario without a relay implementation
      change.

## Implementation order

1. `feature-fresh-session-shutdown-and-recoverable-delivery-retry-contract`
2. In parallel under the same feature owner after step 1:
   - `feature-fresh-session-shutdown-and-recoverable-delivery-managed-shutdown-drain`
   - `feature-fresh-session-shutdown-and-recoverable-delivery-durable-mobile-resend`
3. `feature-fresh-session-shutdown-and-recoverable-delivery-boundary-e2e-proof`
4. Run complete extension, app, protocol, and root pairing verification; then
   advance the feature to review for the caller-selected one standard pass.

## Simplification

- Delete the fixed-delay fresh-session exit.
- Consolidate hot-reload and fresh-session prompt rejection behind one owner-
  delivery fence and one generated error code.
- Replace app transcript scanning plus `_resentHeldPendingIds` as resend
  authority with one encrypted outbox; retain transcript `held` only as a fact
  used by projection/UI.
- Keep `EXIT_FRESH_SESSION`, the wrapper/daemon one-shot fresh launch, existing
  secure-channel sequencing, room snapshots, and extension ingress idempotency.
- Do not add a relay queue, protocol version, generic command journal, or new UI.

## Testing

- **Interface tests — extension lifecycle**: deterministic barriers around an
  accepted SDK delivery, protected outbound sequence reservation, relay stop,
  and mesh close prove ordering. These protect the restart-wrapper incident's
  real boundary; elapsed sleeps are forbidden.
- **Interface tests — app outbox**: encrypted adapter reopen, target-checked
  confirmation, owner-transition wipe, and malformed-record failure protect
  durable state from silent loss or cross-owner survival.
- **Regression tests — SyncService**: quiesced `delivery_retry`, offline and
  sent-but-unconfirmed recovery, session rotation, stale old-session echo,
  history confirmation, failed resend, and cold reopen protect the swallow-fix
  lineage and reconnect state machine.
- **Cross-component test**: real schema codec, owner-channel AEAD, relay route,
  SyncService, room snapshot, and SDK adapter cover quiesce → no delivery →
  restart → resend → confirmation.
- **Existing tests retained**: wrapper exit-42 one-shot launch, direct SDK
  replacement context re-arm, owner-channel drain, session gate, and transcript
  live/replay identity.
- **Test removal**: replace fixed-100-ms fake-timer assertions and the
  held-only resend-selection tests with ordering/outbox contract assertions;
  do not keep both policies.
- **Verification**:
  - `corepack pnpm --dir protocol check`
  - from `pi-extension/`: redirected-cache `corepack pnpm typecheck &&
    corepack pnpm test && corepack pnpm build`
  - from `app/`: `flutter analyze` and `flutter test --exclude-tags e2e`
  - from repo root: `e2e/run-pairing.sh`

## Risks

- **At-least-once is not exactly-once across a hard boundary**: if acceptance
  happened but every confirmation was lost, a successor-session resend can
  repeat user intent. Same-session stable-id dedupe narrows this, and normal
  graceful drain makes the ambiguous window small; the chosen guarantee is
  explicit no-loss rather than an impossible exactly-once promise.
- **Shutdown can stall on external I/O**: sequence persistence, relay close, or
  SDK delivery may hang. Use explicit barriers in tests and a bounded shutdown
  deadline in production; deadline exhaustion exits/restarts and leaves the app
  outbox authoritative.
- **Durable outbox corruption or key loss**: fail closed and visibly at the
  storage boundary. Never send a prompt whose recovery intent could not be
  persisted, and include the box in existing transcript-storage recovery/wipe
  latches.
- **Late old-session confirmation**: compare the confirmation's canonical
  session with the outbox target before deletion; otherwise a stale frame can
  erase the successor retry.
- **Mixed endpoint rollout**: an older app treats `delivery_retry` as a normal
  failure and lacks the outbox; an older extension cannot emit the fence signal.
  Ship app and extension together and leave the relay untouched.

## Other agent review

- Invoked because: cross-component lifecycle/durable-delivery design is this
  repository's highest-risk defect class.
- Skipped/degraded: this delegated worker context exposes no nested generic
  subagent or peer-review adapter. Per policy, design-time advice is
  non-blocking; implementation/final review remains the caller-selected
  `standard` one-pass fresh-context review.
- Fixed/active blockers: none from an independent pass at design time.
- Parked/rejected: none.
