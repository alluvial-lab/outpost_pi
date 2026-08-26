---
id: feature-cruft-consolidated-cleanup
kind: feature
stage: implementing
tags: [refactor, cleanup]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-26
updated: 2026-08-26
---

# Consolidated cruft cleanup (one behavior-preserving [refactor] pass)

## Brief

Formed by groom 2026-08-26 from three cruft batches that are all
behavior-preserving removals/cleanups — route together through one
`[refactor]` design pass rather than three separate ones.

Sources (bodies retained in `.work/archive/`):
- `backlog-cruft-removal-batch` (8 gate-cruft findings, merged 2026-07-23)
- `backlog-hot-reload-cruft-batch` (gate-cruft C1 + gate-tests T5, v0.4.0)
- `gate-cruft-v050-dead-code-sweep` (2 verified instances, post-hoc v0.5.0)

## Findings (carried forward)

**app/relay batch** (all behavior-preserving):
1. Legacy sync/turn compatibility wrappers — `app/lib/data/sync/sync_service.dart:129-134`; `app/lib/domain/transcript/transcript_projection.dart:7`.
2. Misnamed unbounded-channel test mailbox shim — `relay/src/lib.rs:13-22`.
3. `PresenceTransitions` single-impl pass-through trait — `relay/src/peers/registry.rs:64`.
4. Plan-era relay comments → rewrite as current-state contracts — `relay/src/lib.rs:51-53`; `relay/src/handlers/pi_forward.rs:1`.
5. Boolean equality assertions in relay tests (clippy-rejected) — `relay/src/peers/registry.rs:1233,1248,1263,1294`.
6. Unused `ActorDispatch::Close` variant behind `#[allow(dead_code)]` — `relay/src/handlers/connection_actor.rs:28`.
7. Test-only `parse_hello` passthrough wrapper — `relay/src/auth/challenge.rs:67-69`.
8. Unused Settings relay-URL compatibility projection — `app/lib/ui/settings/viewmodels/settings_viewmodel.dart:65`.

**pi-extension dead code**: `_hotReloadEnabledPath()` / `_runtimeIdentityPath()`
no call sites (`index.ts` ~2671-2685 / ~2695-2707 depending on revision).
⚠️ Verify at design time: the helper removal may already have shipped as
`gate-cruft-unused-hot-reload-path-helpers` (v0.8.0,
`.work/releases/v0.8.0/`) — exclude if gone.

**pi-extension expiry test**: armed-request 5-minute expiry untested
(`index.ts:2842-2847` region) — fake clock just below/above the boundary;
assert no claim, marker, quiescing, or SIGTERM when expired, plus stale-file
cleanup.

**app EPK no-op**: empty conditional `if (out != b64) {}` —
`app/lib/data/transport/epk_encoding.dart:30`. Remove, preserve behavior.

## Verification

Per subproject owning the touched files (pi-extension: typecheck+test+build;
relay: fmt+clippy+test; app: analyze+test). All changes behavior-preserving —
suites must stay green with no assertion changes.

## Design decisions

- This remains a pure `[refactor]` feature. No wire frame, persisted format,
  user-visible setting, relay route, or hot-reload runtime rule changes.
- The old findings were re-verified against the current tree rather than
  trusted by their historical line numbers. Completed v0.4.0/v0.8.0 findings
  are not resurrected as work.
- Child stories are grouped by owning subproject and chained
  app → relay → pi-extension. The dependency chain is sequencing-only; it
  prevents an implementation wave from crossing a subproject boundary while
  keeping this bounded cleanup reviewable as one feature.
- The app's `SyncService` getters are still present, but their historical
  `TranscriptTurnStatus` companion alias is gone. The getters can be removed
  only together with mechanical migration of their in-repository test callers
  to the canonical `AppTurnProjection`; no test assertion may be weakened.
- The relay's `ActorDispatch::Close` is not dead in the current tree: the
  pi-forward rate limiter constructs it and `peer.rs` closes on it. It is
  explicitly excluded rather than forced into this refactor.
- The relay `parse_hello` wrapper is source-visible but only has an in-repo test
  caller; this relay binary/library is not a published crate. The migration
  path is to call `parse_hello_bootstrap` in that test before deleting the
  wrapper.
- No `.agents/skills/refactor-conventions/` catalog exists, so the plan uses
  only the five mandatory refactor lenses.

## Re-verification: verified findings

The following findings still have actionable current-tree evidence:

1. **App SyncService compatibility getters** — the old anchors moved to
   `app/lib/data/sync/sync_service.dart:300-307`; `isWorking`,
   `workingStream`, and `workingReplyTo` remain derived wrappers. The
   `transcript_projection.dart:7` alias finding is only partially current: the
   import is used and `TranscriptTurnStatus` no longer exists.
2. **Relay bounded mailbox test shim** — `relay/src/lib.rs:16-22` still exports
   `bounded_mpsc::unbounded_channel` and `UnboundedReceiver`, and test modules
   still call that misleading name.
3. **Relay PresenceTransitions** — `relay/src/peers/registry.rs:75-96` still
   has one pass-through implementation over `PresenceState`.
4. **Relay forwarding comment drift** — the `lib.rs` mesh-auth comment is
   already current and needs no change, but `relay/src/handlers/pi_forward.rs:18-21`
   still claims peer-wide delivery while the implementation is room-targeted.
5. **Relay test-only auth wrapper** — `relay/src/auth/challenge.rs:67-69`
   remains, with the only caller at `relay/src/auth/auth_test.rs:45`.
6. **Pi-extension expiry coverage** — `pi-extension/src/index.ts:3010-3012`
   still has the strict five-minute expiry guard, but current tests do not
   exercise valid requests just below and above that boundary.
7. **App EPK no-op** — `app/lib/data/transport/epk_encoding.dart:30`
   still contains `if (out != b64) {}` with no side effect.

## Re-verification: skipped findings

- **Relay boolean equality assertions**: skipped. The cited current registry
  assertions already use `assert!` and `assert!(!...)`; the v0.4.0 item records
  this as complete.
- **`ActorDispatch::Close`**: skipped. It is constructed by the current
  pi-forward rate-limit branch and is handled by the WS loop; removal would
  change the close-on-limit behavior.
- **Settings relay URL compatibility projection**: skipped. `effectiveRelayUrl`
  was removed in v0.4.0. Current `relayResolution`, `effectiveRelayLabel`, and
  `relayUrlOverride` are canonical and consumed by the Settings page/tests.
- **Pi-extension `_hotReloadEnabledPath()` and `_runtimeIdentityPath()`**:
  skipped. Neither helper exists in the current source; the v0.8.0 release
  item `gate-cruft-unused-hot-reload-path-helpers` records their removal.
- **`TranscriptTurnStatus` alias**: skipped as already gone. Keep the import at
  `transcript_projection.dart:7`, because the reducer still uses
  `UserMessageStreamingBehavior` from it.

## Refactor Overview

The current actionable set is seven findings across three implementation
surfaces. The highest-value work removes misleading test APIs and redundant
pass-throughs while retaining the shared bounded-mailbox constant and
canonical turn/protocol projections. A small stale-contract comment repair and
one lifecycle-boundary test close the remaining drift without changing runtime
semantics.

## Refactor Steps

### Step 1: Collapse app turn compatibility wrappers and remove the EPK no-op

**Priority**: Medium (turn API cleanup), Low (empty branch)
**Risk**: Medium
**Source Lens**: elimination / dead weight
**Files**: `app/lib/data/sync/sync_service.dart`,
`app/lib/data/transport/epk_encoding.dart`, and the in-repository app tests
that still call the removed getters.
**Story**: `feature-cruft-consolidated-cleanup-step-1-app`

**Current State**:

```dart
// sync_service.dart
AppTurnProjection get turnProjection => _turnView.toAppProjection();
Stream<AppTurnProjection> get turnProjectionStream =>
    _turnViewController.stream.map((turn) => turn.toAppProjection());

bool get isWorking => turnProjection.working;
Stream<bool> get workingStream =>
    turnProjectionStream.map((projection) => projection.working).distinct();
String? get workingReplyTo => turnProjection.cancelTargetId;

// epk_encoding.dart
final out = base64.encode(bytes);
if (out != b64) {
}
return out;
```

**Target State**:

```dart
// sync_service.dart — canonical projection only
AppTurnProjection get turnProjection => _turnView.toAppProjection();
Stream<AppTurnProjection> get turnProjectionStream =>
    _turnViewController.stream.map((turn) => turn.toAppProjection());

// epk_encoding.dart
final out = base64.encode(bytes);
return out;
```

All app test callers must use `turnProjection.working`,
`turnProjection.cancelTargetId`, or a boolean projection derived from
`turnProjectionStream` with `.distinct()`. The existing assertions and EPK
conversion matrix remain intact.

**Implementation Notes**:

- Search `app/lib/` and `app/test/` for the exact `SyncService` getter names
  before editing; do not confuse them with unrelated ViewModel `isWorking`
  state fields.
- `transcript_projection.dart:7` is a live import, not a stale alias.
- This is an internal API migration performed atomically in the app story; no
  published app package compatibility promise exists.

**Acceptance Criteria**:

- [ ] No `SyncService` compatibility getter or caller remains.
- [ ] Turn and EPK tests retain their existing observable assertions.
- [ ] `flutter analyze` passes with only the documented unrelated info.
- [ ] `flutter test --exclude-tags e2e` passes.

**Rollback**: Revert the app story commit; restore the three derived getters
and the no-op branch if a caller migration unexpectedly exposes a contract.

---

### Step 2: Make relay test channels explicit, remove the presence indirection, and repair forwarding/auth contracts

**Priority**: High (misleading boundedness and redundant abstraction), Medium
(comment contract), Low (parser wrapper)
**Risk**: Low
**Source Lens**: elimination / code smell / pattern drift
**Files**: `relay/src/lib.rs`, `relay/src/peers/registry.rs`,
`relay/src/handlers/control.rs`, `relay/src/handlers/connection_actor.rs`,
`relay/src/handlers/pi_forward.rs`, `relay/src/auth/challenge.rs`, and
`relay/src/auth/auth_test.rs`.
**Story**: `feature-cruft-consolidated-cleanup-step-2-relay`

**Current State**:

```rust
// lib.rs test support
pub(crate) mod bounded_mpsc {
    pub(crate) use tokio::sync::mpsc::Receiver as UnboundedReceiver;
    pub(crate) fn unbounded_channel<T>()
        -> (tokio::sync::mpsc::Sender<T>, tokio::sync::mpsc::Receiver<T>) {
        tokio::sync::mpsc::channel(OUTBOUND_QUEUE_CAPACITY)
    }
}

// peers/registry.rs
trait PresenceTransitions { /* two methods */ }
impl PresenceTransitions for PresenceState { /* direct delegation */ }

// handlers/pi_forward.rs
//! Cross-PC data-plane forwarding is peer-wide in this slice.

// auth/challenge.rs
pub fn parse_hello(line: &str) -> Result<VerifyingKey, AuthError> {
    Ok(parse_hello_bootstrap(line, 0)?.verifying_key)
}
```

**Target State**:

```rust
// Test modules use the real bounded API and shared capacity.
use crate::resource_limits::OUTBOUND_QUEUE_CAPACITY;
use tokio::sync::mpsc;

let (tx, rx) = mpsc::channel::<Message>(OUTBOUND_QUEUE_CAPACITY);
// helper signatures use mpsc::Receiver<Message>

// registry.rs calls PresenceState's inherent methods directly; no trait or
// pass-through impl remains.

// pi_forward.rs module contract
//! Cross-PC data-plane forwarding is room-targeted: `to_room` selects the
//! destination room on `to_pc`; the sender's own connection is skipped. The
//! envelope body remains endpoint-owned opaque data.
```

The auth test calls `parse_hello_bootstrap(&line, 0)` and retains the same
`AuthError::NoHello` assertion. The `lib.rs` `mesh_auth` comment is left as-is
because it already describes the current bounded cache contract.

**Implementation Notes**:

- Remove the compatibility module rather than renaming its misleading alias;
  update all test-only imports/calls in the control, connection-actor, and
  registry fixtures to pass `OUTBOUND_QUEUE_CAPACITY` explicitly.
- Do not alter production `ConnectionRegistry` channels or the resource-limit
  constant. The test migration must continue to model the same bounded mailbox.
- Remove `parse_hello` only after its single test caller has migrated. The
  symbol-removal migration is the rollback boundary for this internal API.
- Leave `ActorDispatch::Close` and the already-fixed boolean assertions alone.

**Acceptance Criteria**:

- [ ] No test-support `unbounded_channel` or `UnboundedReceiver` compatibility
      name remains.
- [ ] `PresenceTransitions` has no declaration or implementation, and online/
      offline transition tests retain their meaning.
- [ ] `pi_forward.rs` describes room-targeted, opaque forwarding accurately.
- [ ] Auth tests use `parse_hello_bootstrap` and preserve the error assertion.
- [ ] `cargo fmt --check`, `cargo clippy -- -D warnings`, and `cargo test` pass.
- [ ] No relay wire, routing, backpressure, or persistence behavior changes.

**Rollback**: Revert the relay story commit. This restores only test naming,
comments, and indirection; it does not require data or protocol migration.

---

### Step 3: Add deterministic armed-request expiry boundary coverage

**Priority**: Medium
**Risk**: Medium
**Source Lens**: dead weight / lifecycle regression protection
**Files**: `pi-extension/src/index.ts` (read-only contract anchor) and
`pi-extension/src/extension.test.ts`.
**Story**: `feature-cruft-consolidated-cleanup-step-3-pi-extension`

**Current State**:

```ts
if (typeof request.ts === "number" && Date.now() - request.ts > 5 * 60_000) {
  _removeIfOwnerOnlyRegularFile(armedPath);
  return;
}
```

The valid-nonce expiry branch has no just-below/just-above boundary test.

**Target State**:

The existing production code remains unchanged. Tests use a fake clock and a
real armed request produced by the hot-reload command:

```ts
vi.useFakeTimers();
vi.setSystemTime(baseTime);
await arm("arm", makeMockCtx());
vi.setSystemTime(baseTime + 5 * 60_000 + 1);
onSettled({ type: "agent_settled" }, { isIdle: () => true });
expect(killSpy).not.toHaveBeenCalled();
expect(existsSync(armedPath)).toBe(false);
expect(existsSync(claimedPath)).toBe(false);
expect(existsSync(markerPath)).toBe(false);
```

A just-below case proves the strict `>` boundary still claims and signals. A
fresh request after the expired case proves no quiescing latch survived.

**Implementation Notes**:

- Use `vi.setSystemTime` rather than sleeps or elapsed wall-clock loops.
- Preserve the production nonce by invoking the existing `arm` handler; do not
  fabricate a valid request by bypassing the nonce check.
- Isolate temporary hot-reload directories and reset fake timers, environment,
  spies, `_disposed`, and `_hotReloading` in `finally` blocks.
- Treat this as a test addition. Do not weaken or remove existing hot-reload
  assertions and do not alter the five-minute predicate.

**Acceptance Criteria**:

- [ ] Just-below expiry is accepted and writes the claim/marker before the
      mocked SIGTERM path.
- [ ] Just-above expiry performs no claim, marker write, quiescing latch, or
      SIGTERM and removes the stale armed file.
- [ ] A fresh request can restart after the expired case, proving the fence was
      not latched.
- [ ] `corepack pnpm typecheck`, `corepack pnpm test`, and `corepack pnpm build`
      pass.

**Rollback**: Remove only the new boundary test; the existing expiry guard and
other hot-reload lifecycle tests remain unchanged.

## Implementation Order

1. `feature-cruft-consolidated-cleanup-step-1-app` — app projection/EPK cleanup
   (`depends_on: []`).
2. `feature-cruft-consolidated-cleanup-step-2-relay` — explicit bounded test
   mailboxes, presence simplification, current forwarding/auth contracts
   (`depends_on: [feature-cruft-consolidated-cleanup-step-1-app]`).
3. `feature-cruft-consolidated-cleanup-step-3-pi-extension` — expiry boundary
   test (`depends_on: [feature-cruft-consolidated-cleanup-step-2-relay]`).
