---
id: feature-lifecycle-disposal-async-void
kind: feature
stage: done
tags: [pi-extension, app, lifecycle]
parent: null
depends_on: []
release_binding: v0.4.0
gate_origin: refactor
created: 2026-07-28
updated: 2026-08-11
---

# Lifecycle disposal + unguarded-async-void convergence

## Brief
Five `gate-refactor` findings (scan library `lifecycle`, rules
`resource-no-dispose` and `unguarded-async-void`) identify resources and async
teardown paths that escape owned lifecycle boundaries across the extension and
app. This is the repo's highest-risk defect class (per
`.agents/rules/testing-integrity.md` — async and lifecycle). Two rules:

`resource-no-dispose` — a registered resource (stream subscription, WebSocket
listener, watcher) has no disposal hook on its owning lifecycle boundary:
- `gate-refactor-lifecycle-owner-identity-watcher-no-dispose` —
  `app/lib/config/dependencies.dart:96` `OwnerIdentityBridge` owns a platform
  stream subscription with `dispose()` but `addInstance` provides no disposal
  hook, so `disposeDependencies()` never cancels it.
- `gate-refactor-lifecycle-relay-auth-timeout-listener` —
  `pi-extension/src/transport/relay_client.ts:253` auth timeout rejects without
  removing the `ws.once("message")` listener, leaving a stale listener.

`unguarded-async-void` — an async teardown is fire-and-forget, racing shutdown
or dropping rejections:
- `gate-refactor-lifecycle-bye-frames-race-relay-shutdown` —
  `pi-extension/src/index.ts:943` `_goIdle` enqueues protected bye frames,
  detaches channels, and closes the relay without awaiting each secure
  channel's persistence/send drain.
- `gate-refactor-lifecycle-owner-ingress-floating` —
  `pi-extension/src/index.ts:319` the relay outer-message callback voids
  `_handleOwnerOuterFrame(...)` without awaiting or attaching a rejection
  handler.
- `gate-refactor-lifecycle-self-revoke-discards-async-detach` —
  `pi-extension/src/extension/command_surface/pairing_coordinator.ts:213`
  `onRevoke` discards the `Promise` from `owners.detach` though `SelfRevoke`
  supports and awaits async callbacks.

## Simplification opportunity
A single owned-async-teardown boundary (named cleanup shared by timeout/success
paths; an awaited `whenIdle` before relay close; a rejection observer on
floating ingress) removes five independent leaks and the unhandled-promise-
rejection class they invite. Coordinate with the already-advanced
`gate-patterns-inconsistency-pairing-coordinator-stale-capability` story (same
stale-capability-across-replacement class, same `pairing_coordinator.ts` file).

## Design notes
Scan library `scan-lifecycle` declares `findings-route: none` (fixes are not
black-box-preserving — they change teardown ordering/await behavior), so this
routes through `feature-design`, not `refactor-design`. The design pass should
sequence: the bye-frames race and the auth-timeout listener are the highest-
risk (shutdown ordering / stale WebSocket listener); the floating ingress and
self-revoke async-detach are unhandled-rejection sources; the app identity-
watcher is a pure disposal-binding fix. Verify each with the lifecycle/async
tests (`scan-lifecycle` rule library + existing turn-state/projection suites).

## Design decisions
- **Owner-channel shutdown is an awaited end-to-end contract**: make `_goIdle` return `Promise<void>`, propagate that promise through runtime and command stop ports, detach each owner with the requested bye reason, await every returned channel drain, and only then close the relay. This preserves the final protected frame instead of merely enqueueing it.
- **The secure-channel drain remains relay-independent**: `SecurePeerChannel.whenIdle()` may wait for local sequence reservation/persistence, synchronous WebSocket enqueue, inbound work already accepted, and bounded audit writes; it must never wait for a relay ACK, a future relay message, or relay close. The shared relay stays open until all detach drains settle.
- **Teardown is best-effort but rejection-observed**: aggregate owner drains with `Promise.allSettled`, optionally record only a payload-free failure category/count, and continue closing the relay. One failed channel must not strand the whole runtime or surface an unhandled rejection.
- **Auth wait owns one cleanup function**: `_nextMsg` uses named message/timeout callbacks and a single settlement guard. Timeout and success both clear the timer, remove the pending message listener, and settle exactly once; any close/error listeners added later must join the same cleanup.
- **Owner ingress uses the transport-owned async dispatch boundary**: retain the current implicit return from the `onOuterMessage` callback. `RelayTransport` awaits that promise inside its generation-fenced FIFO and observes handler rejection before continuing. Do not add a second fire-and-forget observer in `index.ts`.
- **Self-revoke awaits channel teardown**: make `onRevoke` async and await `owners.detach(ownerEpk, "session_replaced")` before publishing the local revoke notice. `SelfRevoke` already accepts and awaits async callbacks.
- **The app injector owns `OwnerIdentityBridge` disposal**: extend `CustomInjector.addInstance` with an optional typed `onDispose` callback and register the bridge with `bridge.dispose()`. Keep `disposeDependencies()` as the single composition-root teardown rather than adding a one-off manual lookup there.
- **Existing lifecycle fixes are preserved**: build on the stale-capability handling from `14c1966` and keep the `working=false` convergence from `b5fa094` ordered before the final relay close.

## Architectural choice
Use owned promises at each existing lifecycle boundary rather than adding a new teardown coordinator. `_goIdle`, relay auth, relay ingress, self-revoke, and the app injector already have clear owners; the fix is to make their completion and cleanup contracts explicit and propagate them to callers.

Two alternatives were rejected. Keeping synchronous APIs and attaching `.catch()` observers would prevent unhandled rejections but would not guarantee bye delivery or teardown order. A cross-cutting lifecycle manager could centralize every socket, stream, and timer, but would duplicate ownership already expressed by `RelayTransport`, `OwnerMultiplexer`, `SelfRevoke`, and `CustomInjector` and enlarge a focused correctness fix.

Direct reading was sufficient: the five sites and their tests are bounded, and the owner-ingress finding has already partially converged on the intended promise-return pattern at current HEAD.

## Implementation units

### Unit 1: Await secure owner drains before relay shutdown
**Story**: `gate-refactor-lifecycle-bye-frames-race-relay-shutdown`

**Files**:
- `pi-extension/src/index.ts`
- `pi-extension/src/extension/ports.ts`
- `pi-extension/src/extension/composition_root.ts`
- `pi-extension/src/extension/command_surface/local_mesh_commands.ts`
- `pi-extension/src/extension/command_surface/control_commands.ts`
- matching tests in `pi-extension/src/extension.test.ts`, `pi-extension/src/extension/composition_root.test.ts`, and command-surface suites

```ts
function _goIdle(byeReason?: ByeReason): Promise<void>;

export interface RelayTransportPort {
  stop(reason?: ByeReason): Promise<void>;
}

export interface LocalMeshCommandsDeps {
  readonly stopRelay: (reason?: ByeReason) => Promise<void>;
}

export interface ControlCommandsDeps {
  readonly stopRelay: (reason?: ByeReason) => Promise<void>;
}
```

**Implementation notes**:
- This is the trickiest unit. Stop owner ingress and the self-revoke poller first, snapshot current owner ids, and call `_owners.detach(peerId, byeReason)` once per owner. `detach` already queues the protected bye before detaching its listener and returns `whenIdle()` work.
- Await the snapshot's drains with `Promise.allSettled` before `_relayTransport.stop(byeReason)`. Remove the separate `_owners.broadcast(bye)` plus `_owners.detachAll()` sequence so each owner gets one bye through the drain-aware path.
- Coalesce overlapping `_goIdle` calls behind one in-flight promise so control shutdown and `session_shutdown` cannot race two teardown sequences.
- Preserve turn convergence before final relay close. The `b5fa094` composition-root contract remains: `resetTurnSnapshot()` and any `working=false` publish occur while the relay is usable.
- Await `ports.relay.stop()` in `disposeRuntimePorts`; await `stopRelay` from `/outpost-pi stop`, Cockpit relay off/toggle, and rename relay cycling. Update port fakes rather than weakening the async signature.
- Do not add relay-response waiting to `whenIdle`: outbound `relay.send` is the terminal transport action and is synchronous from the drain's perspective.

**Acceptance criteria**:
- [ ] With a sequence-persistence barrier holding the bye, `_goIdle` remains pending and the relay has not closed; releasing the barrier emits the protected bye and only then closes the relay.
- [ ] Every attached owner is detached once with the supplied bye reason, and one drain rejection is observed without blocking final relay close.
- [ ] Concurrent stop requests share one teardown and do not duplicate byes or relay close.
- [ ] `session_shutdown`, slash-command stop, control stop/toggle, and rename all await the same completion boundary.
- [ ] Working-state convergence still occurs before relay close.

### Unit 2: Settle relay auth waits exactly once
**Story**: `gate-refactor-lifecycle-relay-auth-timeout-listener`

**Files**:
- `pi-extension/src/transport/relay_client.ts`
- `pi-extension/src/transport/relay_client.test.ts`

```ts
private _nextMsg(ws: WebSocket): Promise<string>;

// Local named callbacks inside _nextMsg:
function cleanup(): void;
function onMessage(raw: WebSocket.RawData): void;
function onTimeout(): void;
```

**Implementation notes**:
- Keep `_nextMsg` private and preserve its external error text. Use a `settled` guard and one cleanup function shared by the timeout and message paths.
- Cleanup clears the auth timer and removes the exact named `message` callback. If close/error rejection is added, register named callbacks and remove them in the same cleanup rather than creating parallel settlement paths.

**Acceptance criteria**:
- [ ] Auth timeout rejects once and leaves `ws.listenerCount("message") === 0`.
- [ ] Successful challenge clears the timeout and removes the pending auth listener before post-auth message forwarding begins.
- [ ] A message/timeout race cannot resolve and reject the same wait or consume a later data-plane frame.

### Unit 3: Keep owner ingress inside the owned dispatch promise
**Story**: `gate-refactor-lifecycle-owner-ingress-floating`

**Files**:
- `pi-extension/src/index.ts`
- `pi-extension/src/extension/relay_transport.ts`
- `pi-extension/src/extension/relay_transport.test.ts`

```ts
function _handleOwnerOuterFrame(
  ingress: Extract<DecodedRelayIngress, { kind: "outer" }>,
  connectionIsCurrent: () => boolean,
): Promise<boolean>;

onOuterMessage(
  handler: (
    ingress: Extract<DecodedRelayIngress, { kind: "outer" }>,
    isCurrent: () => boolean,
  ) => boolean | void | Promise<boolean | void>,
): () => void;
```

**Implementation notes**:
- Current HEAD already returns `_handleOwnerOuterFrame(...)` from the registration callback and awaits handlers in `dispatchRelayMessage`. Preserve this shape; do not reintroduce `void` at registration.
- Keep the generation guard (`connectionIsCurrent`) evaluated by the awaited routing work. The retained-dispatch `try/catch/finally` is the owner of rejection observation and accounting release.

**Acceptance criteria**:
- [ ] An explicitly rejected async owner handler produces no process-level unhandled rejection, releases dispatch accounting, and does not prevent a later healthy frame from routing.
- [ ] A stale relay generation cannot attach or publish an owner after its awaited lookup completes.
- [ ] The triggering protected frame remains ordered after successful async owner attachment.

### Unit 4: Await self-revoke owner detach
**Story**: `gate-refactor-lifecycle-self-revoke-discards-async-detach`

**Files**:
- `pi-extension/src/extension/command_surface/pairing_coordinator.ts`
- `pi-extension/src/extension/command_surface/pairing_coordinator.test.ts`

```ts
onRevoke: async (ownerEpk: string): Promise<void> => {
  this.deps.refreshPairingsCache();
  if (this.deps.ownerHas(ownerEpk)) {
    await this.deps.owners.detach(ownerEpk, "session_replaced");
  }
  // publish the existing payload-free local revoke notice
};
```

**Implementation notes**:
- Reuse the existing async `OwnerMultiplexerPort.detach` contract established by Unit 1. Do not add a second detach helper or a nested `void` observer.
- Preserve the stale-UI/capability behavior from `14c1966`; this callback uses injected current capabilities and must not retain a command context across the await.

**Acceptance criteria**:
- [ ] `SelfRevoke.checkOnce()` does not settle or publish its revoke notice until a deferred `owners.detach` settles.
- [ ] The attached owner receives the `session_replaced` reason exactly once.
- [ ] A detach rejection is observed by the awaited self-revoke chain rather than becoming unhandled.

### Unit 5: Bind the Owner identity watcher to app disposal
**Story**: `gate-refactor-lifecycle-owner-identity-watcher-no-dispose`

**Files**:
- `app/lib/config/utils/injector.dart`
- `app/lib/config/dependencies.dart`
- `app/test/config/custom_injector_test.dart` (new focused lifecycle test)
- `app/test/pairing/owner_identity_bridge_test.dart`

```dart
void addInstance<T>(
  T instance, {
  void Function(T value)? onDispose,
});

_injector.addInstance<OwnerIdentityBridge>(
  ownerBridge,
  onDispose: (bridge) => bridge.dispose(),
);
```

**Implementation notes**:
- Adapt the optional callback to `BindConfig<T>(onDispose: onDispose)` in `CustomInjector`; registrations without a callback retain current behavior.
- Keep `disposeDependencies() => _injector.dispose()` as the app-lifetime boundary. Do not make widgets or the router manually own this app-global bridge.

**Acceptance criteria**:
- [ ] Disposing `CustomInjector` invokes an owned instance callback exactly once.
- [ ] The production `OwnerIdentityBridge` registration supplies its `dispose` callback.
- [ ] After bridge disposal, a platform-store emission cannot invoke owner-transition work or retain an active watch subscription.

## Implementation order
1. `gate-refactor-lifecycle-bye-frames-race-relay-shutdown` — establish the awaited owner-detach/relay-stop contract first.
2. `gate-refactor-lifecycle-relay-auth-timeout-listener` — close the independent high-risk WebSocket auth listener leak.
3. `gate-refactor-lifecycle-owner-ingress-floating` — pin the already-present transport-owned promise boundary with rejection regression coverage.
4. `gate-refactor-lifecycle-owner-identity-watcher-no-dispose` — bind the independent app-global watcher to injector disposal.
5. `gate-refactor-lifecycle-self-revoke-discards-async-detach` — consume the awaited detach contract after Unit 1.

Units 2, 3, and 5 are independent and may be implemented in the same feature ownership stride; Unit 4's self-revoke checkpoint is the only declared child dependency.

## Simplification
- Replace `_goIdle`'s duplicate broadcast-plus-detach sequence with one per-owner `detach(peerId, reason)` path that already owns bye enqueue, listener removal, and drain completion.
- Reuse the relay transport's existing FIFO rejection boundary for owner ingress rather than adding a second logger/catch layer in `index.ts`.
- Extend the existing injector registration primitive instead of adding a manual global-disposal list.
- No protocol, persistence, UI, or compatibility surface changes are required.

## Testing
- **Teardown ordering regression** (`extension.test.ts` / composition-root tests): use explicit started/release barriers around secure-channel sequence persistence; assert bye drain precedes relay close and `working=false` remains publishable before close. This protects the production race, not implementation line coverage.
- **Auth listener lifecycle** (`relay_client.test.ts`): use Vitest fake timers, assert listener counts on timeout and success, and prove exactly-once settlement without sleeps.
- **Ingress rejection ownership** (`relay_transport.test.ts`): reject an async handler, then route a healthy frame and assert accounting/generation progress with no unhandled rejection.
- **Self-revoke ordering** (`pairing_coordinator.test.ts`): defer `owners.detach` and assert callback completion/notice ordering.
- **App watcher disposal** (`custom_injector_test.dart`, `owner_identity_bridge_test.dart`): prove injector callback invocation and no post-dispose platform event delivery.
- Run targeted suites first, then `corepack pnpm typecheck`, `corepack pnpm test`, `flutter analyze`, and `flutter test --exclude-tags e2e` from their owning subprojects. Use `--concurrency=2` for the load-sensitive Flutter full suite.
- Do not remove existing turn-state, projection, secure-channel, reconnect, or stale-context regressions; they cover adjacent lifecycle guarantees.

## Risks
- **Deadlock while awaiting bye drains (highest risk)**: shutdown would hang if `whenIdle()` ever waited for an ACK/future frame from the relay that `_goIdle` is responsible for closing. The design forbids that dependency: the drain ends after local persistence and synchronous WebSocket enqueue, and a barrier test asserts relay close waits on that local work. If a future reliable-send protocol needs ACKs, it must expose a bounded pre-close flush contract rather than silently extending `whenIdle`.
- **Concurrent stop/restart interleaving**: making stop async creates a window where another lifecycle trigger can enter. One in-flight `_goIdle` promise plus awaited command/runtime call sites prevents duplicate teardown; tests must cover concurrent stops.
- **A failed per-owner drain could strand global shutdown**: `Promise.allSettled` observes every rejection and guarantees relay teardown continues. Diagnostics must contain only category/count, never owner ids or payloads.
- **Owner-ingress finding is partially stale at current HEAD**: the promise return and awaited FIFO already exist. Implementation should add/confirm rejection coverage and avoid rewriting a working boundary merely to create a diff.
- **Injector test isolation**: the production injector is module-global and committed after setup. Test the generic disposal binding with a fresh `CustomInjector` and the bridge cancellation separately rather than re-running production bootstrap in one process.

## Open questions
None. The feature changes lifecycle guarantees and teardown ordering only; it introduces no open product-direction or external-contract decision.

## Implementation summary

Completed checkpoints:
- `gate-refactor-lifecycle-bye-frames-race-relay-shutdown` — awaited/coalesced owner drains now precede relay close across every stop surface.
- `gate-refactor-lifecycle-self-revoke-discards-async-detach` — self-revoke awaits owner detach before its local notice.
- `gate-refactor-lifecycle-owner-ingress-floating` — the existing transport-owned promise boundary is pinned by async-rejection/no-unhandled regression coverage.
- `gate-refactor-lifecycle-relay-auth-timeout-listener` — auth wait cleanup now removes the exact listener on timeout and success.
- `gate-refactor-lifecycle-owner-identity-watcher-no-dispose` — completed by the app owner and integrated in the shared feature.

Deviations: the owner-ingress production boundary had already converged at HEAD, so that checkpoint added regression evidence without rewriting working source. Self-revoke gained a narrow poller-factory test seam to verify callback ordering without network polling.

Integrated pi-extension verification: `tsc --noEmit` passed; final `vitest run` passed 950 tests with 3 skipped across 55 files.
