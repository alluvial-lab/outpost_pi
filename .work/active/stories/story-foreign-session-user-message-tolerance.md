---
id: story-foreign-session-user-message-tolerance
kind: story
stage: done
tags: [pi-extension, app, bug]
parent: feature-session-stable-message-delivery
depends_on:
  - feature-session-stable-message-delivery-stale-wake-tolerance
release_binding: null
gate_origin: null
created: 2026-07-04
updated: 2026-07-11
review_origin: deep-review 2026-07-04
---

# Cross-process foreign-session `user_message` still surfaces a visible error

## Origin

Surfaced as a Blocker in the deep review of
`feature-session-stable-message-delivery-stale-wake-tolerance`. The tolerance
fix only covers the **same-session stale wake** case. The cross-process
**foreign-session** case (the original operator scenario: two pis on same
machine+cwd+identity, phone message fans out to both) is NOT covered.

## The gap

`user_message` is session-scoped (`session_scope.ts`). When the relay fans a
phone `user_message` out to a duplicate/idle pi whose `currentRemoteSessionId`
differs from the phone's `session_id`, `_routeClientMessageFrom`'s
`validateClientSession` gate rejects it BEFORE `_deliverUserMessage`/`wakeAgent`,
emitting `error{code:"session_mismatch"}` (`index.ts:2070-2079`,
`session_gate.ts:14-30`). The app renders generic errors as a ⚠ assistant-error
row (`app/lib/data/sync/sync_service.dart:729-746`).

So the duplicate/idle pi still produces a visible error on the phone — just
`session_mismatch` instead of `internal_error: …stale…`. The broad "idle/wrong
pi is benign" design intent is not achieved.

## Why this is hard (design needed, do NOT one-line-fix)

A pi **cannot distinguish** two cases from the `user_message` alone:

1. **Duplicate delivery to the wrong pi** (cross-process fanout, this bug) —
   should be silently tolerated.
2. **Phone held a stale `session_id` and is legitimately re-syncing** after a
   replacement — the `session_mismatch` error is the *intended* signal that
   tells the phone "your session_id is stale, re-sync via `session_sync`."
   Silently tolerating it would break the re-sync path.

So blindly dropping `session_mismatch` for `user_message` is wrong. The
disambiguation needs design — candidates to evaluate at design time:

- **Distinguish by sender/origin.** A `user_message` from a known owner peer
  that just paired (vs. a re-sync from an existing owner) might carry different
  signals. Investigate whether the relay or the envelope can distinguish
  "duplicate delivery" from "stale client session_id."
- **Tolerate only when this pi is idle AND not the intended target.** If this
  pi has no active turn and another pi on the same (owner_pk, room) is
  working, treat the foreign-session `user_message` as benign. Requires
  knowing about the sibling pi — non-trivial cross-process state.
- **Suppress the app-side rendering of `session_mismatch` for `user_message`.**
  App-side change: don't render `session_mismatch` on a `user_message`
  in-reply-to as a ⚠ row; treat it as a benign drop + trigger a `session_sync`.
  Smallest fix, but moves the tolerance to the app and may mask the legitimate
  re-sync signal for *all* session mismatches, not just duplicates.
- **Prevention (out of scope here, tracked in the parent feature):** refuse a
  second pi on the same identity+room. Conflicts with multi-device-owner
  design.

## Acceptance criteria (to be refined at design)

- [ ] A duplicate-delivered foreign-session `user_message` to an idle pi does
  NOT surface a visible error on the phone.
- [ ] A legitimate stale-`session_id` re-sync still produces the signal that
  triggers `session_sync` (the re-sync path is NOT broken).
- [ ] Regression test for both cases.

## References

- Parent feature: `feature-session-stable-message-delivery.md`.
- Sibling (same-session tolerance, done): `feature-session-stable-message-delivery-stale-wake-tolerance.md`.
- `pi-extension/src/index.ts:2070-2079` — the session gate that emits `session_mismatch`.
- `pi-extension/src/session/session_gate.ts:14-30` — `validateClientSession`.
- `app/lib/data/sync/sync_service.dart:729-746` — app renders `ErrorMessage` as ⚠ row.
- Relay fanout: `relay/src/peers/connections.rs:94-114`, `relay/src/peers/registry.rs:33`.

## Grounding findings (2026-07-11)

The original framing is too broad. Direct reading of the app and extension
confirms that the app already has the second session boundary the original
review missed:

1. `app/lib/data/sync/sync_service.dart::_onServerMessage` calls
   `SessionGate.accepts` before the `ErrorMessage` switch arm.
2. `error` is session-scoped in the generated protocol registry (projected
   through `app/lib/protocol/protocol.dart`) and the extension's mismatch reply
   carries the rejecting Pi's current `session_id`.
3. `SyncService._activeRef` is derived from
   `ConnectionManager.activeSessionId`, whose authority is the active room's
   latest `RoomInfo.sessionId` from `pair_ok` / room metadata.

Therefore, if the phone sends a message for session B and duplicate Pi A replies
with `error{code:"session_mismatch", session_id:A}`, the ordinary state is
`activeRef=B`; the app gate rejects A's error and no warning row is written.
This is already covered generically by the existing foreign-error gate test,
but not by a correlated pending-user-message characterization test.

The exact remaining visible-warning window is the opposite ordering from the
initial hypothesis: the warning can render only when room metadata has already
rotated the app to the rejecting Pi's session before its mismatch error reaches
`SyncService`.

```text
send user_message(session_id=old/B)
  -> rejecting Pi replies session_mismatch(session_id=new/A)
  -> if activeRef is still old/B: app gate drops the error silently
  -> if room metadata has first rebound activeRef to new/A: gate accepts the
     error and the generic ErrorMessage arm writes `⚠ session_mismatch: ...`
```

This ordering applies both to cross-Pi last-writer metadata churn and to a
single Pi after session replacement. During the 50 ms room-stream debounce,
`ConnectionManager.activeSessionId` may already be new while
`SyncService._activeRef` remains old; the error is still rejected until
`_onRoomsChanged` rebinds the service.

The send timers do not create the warning:

- A gate-rejected foreign mismatch never reaches the error handler and does not
  cancel or extend `_pendingSendTimers`; the intended Pi's echo still confirms
  the message, otherwise the existing 20 s no-echo backstop produces the
  accurate failed-user-message state.
- A canonical session rotation calls `activate`, whose
  `_resetTurnState(clearPendingSendTimers: true)` cancels timers owned by the
  old session. A later accepted mismatch currently creates the separate ⚠ row;
  it does not drive `_onSendTimeout` or the `delivery_pending` timer.
- The real resync gap is that `_onRoomsChanged` rebinds on session-id rotation
  but does not itself request `session_sync`. Thus merely suppressing the
  warning would not satisfy the legitimate replacement path.

Dispatch rationale: direct-read only. The behavior is bounded to the existing
app session gate, room-metadata rebind, and send timer code; no exploratory
fanout was needed.

## Design decisions

- **Where is the ambiguity resolved?** At the app, using its two existing
  authorities: `SessionGate` decides whether a server frame belongs to the
  currently bound session, while room metadata decides which session becomes
  canonical. The extension cannot distinguish duplicate fanout from a stale
  client using the request alone and remains fail-closed.
- **What does `session_mismatch` mean in the UI?** It is a convergence/control
  signal, not transcript content. The app never renders this code as an
  assistant warning. Other error codes retain the generic visible-error path.
- **What triggers legitimate resync?** A canonical `RemoteSessionRef` rotation
  observed in `_onRoomsChanged`, not the mismatch error's untrusted session id.
  The rotation sets the existing `_pendingSyncRequest` latch before `activate`;
  `activate` drains that latch only after the new session box is bound. This
  reuses the current single source of truth for deferred sync and never adopts
  a session id from an error frame.
- **Are child stories warranted?** No. The production change and its tests are
  one tightly cohesive app-side stride; the extension and relay contracts do
  not change.

## Architectural choice

Choose **app-side convergence using the existing gate plus metadata-driven
resync**.

The extension continues to reject every foreign session-scoped command and to
return its current `session_id`; this preserves fail-fast protection and the
re-sync signal. The app keeps `SessionGate` unchanged: foreign mismatch errors
remain silently rejected before mutation. For the narrower ordering where the
error matches the now-current session, `SyncService` recognizes only the known
`session_mismatch` code as non-transcript control and suppresses the generic ⚠
projection. Independently, every room-metadata session-id rotation arms the
existing deferred-sync latch before rebinding, so the newly canonical session
receives `session_sync` after activation.

Rejected alternatives:

- **Extension-side silent tolerance / origin heuristics:** cannot distinguish
  duplicate fanout from a legitimately stale phone and would weaken the
  session boundary.
- **Adopt or sync directly to `ErrorMessage.sessionId`:** lets a duplicate Pi's
  response select app state and risks a mismatch loop. Room metadata remains
  the only canonical-session authority.
- **Sibling-working/process coordination or duplicate-Pi prevention:** adds
  cross-process authority and changes product topology for a race already
  resolvable at the app boundary.
- **Only suppress the warning:** closes the symptom but leaves replacement
  hydration accidental; rejected because the acceptance criterion requires a
  real `session_sync` path.

## Implementation units

### Unit 1: Treat mismatch as control and sync after canonical rotation

**File:** `app/lib/data/sync/sync_service.dart`

Keep the public API unchanged. Modify these existing private paths:

```dart
void _onRoomsChanged() {
  _writeRuntime();
  final epk = _activeEpk;
  if (epk == null) return;
  final nextRef = _resolveActiveRef(epk, _activeRoomId);
  if (nextRef != _activeRef) {
    _pendingSyncRequest = true;
    // ignore: discarded_futures
    activate(epk, _activeRoomId);
  }
}

void _onServerMessage(ServerMessage msg, [String? originEpk]) {
  // Existing origin and SessionGate checks remain first.
  // ...
  switch (msg) {
    // ...
    case ErrorMessage(:final inReplyTo, :final code, :final message):
      if (code == 'session_mismatch') {
        break; // convergence signal; never transcript content
      }
      // Existing delivery_pending / unknown_peer / visible-error behavior.
  }
}
```

Implementation notes:

- Set `_pendingSyncRequest` before the async `activate` call. Existing
  `activate` drains it after `_loadIndex` / projection materialization and
  `requestSync` clears it, avoiding a second sync mechanism or ad-hoc timer.
- Do not bypass or relax `SessionGate`; the special case only affects a
  mismatch error that the gate has accepted for the now-current session.
- Do not cancel pending-send timers in the mismatch arm. Timer lifecycle stays
  owned by echo, session activation, cancel, timeout, and dispose.
- Preserve visible handling for `internal_error`, provider failures, unknown
  future codes, and the existing `delivery_pending` extension behavior.

Acceptance criteria:

- [ ] A foreign-session mismatch reply is dropped by `SessionGate` without a
      warning row and without disturbing the pending send's timer.
- [ ] An accepted current-session mismatch reply also creates no warning row.
- [ ] A room metadata session-id rotation sends `SessionSync` for the new id
      after `SyncService.activeSessionRef` has rebound.
- [ ] No `SessionSync` is targeted from a foreign error's session id alone.

### Unit 2: Pin the protocol semantics

**File:** `PROTOCOL.md`

Refine the known-error-code entry for `session_mismatch`: the extension rejects
a command targeting another session; the app treats the reply as a
non-transcript convergence signal, and canonical room/session metadata—not the
error payload—drives rebind plus `session_sync`. This is a current protocol
semantic, not implementation history.

Acceptance criteria:

- [ ] The durable protocol reference states both fail-closed rejection and
      non-visible app handling without claiming the relay can disambiguate
      sessions.

## Testing

**File:** `app/test/data/sync/sync_service_test.dart`

Add focused tests through a real `ConnectionManager` + `SyncService`, using the
existing `_FakeChannel`, `PairOk` session-rotation fixture, and short pending
send timeout where needed:

1. **Cross-Pi duplicate characterization.** Send a local `UserMessage` for
   session B, then inject a correlated
   `ErrorMessage(sessionId:A, code:'session_mismatch')`. Assert no assistant ⚠
   row, active session remains B, no `SessionSync` targets A, and the pending
   send timer remains armed until its normal echo/timeout owner resolves it.
2. **Replacement ordering regression.** Send against old session B; inject the
   new-session mismatch once before metadata rebind (gate-rejected), then
   publish `PairOk(sessionId:new)` and allow room debounce + activation to
   settle, then inject it again after rebind (gate-accepted). Assert neither
   ordering writes a ⚠ row and exactly one or at least one (depending on
   pre-existing eager-sync fixtures) `SessionSync(sessionId:new)` is emitted
   after the active ref becomes new. Assert no sync is sent with old/B after
   the rotation assertion point.
3. Keep the existing generic `internal_error` test proving non-mismatch errors
   still render visibly, so the suppression cannot broaden unnoticed.

The mandatory behaviors are both covered at the app integration seam: (a) a
foreign duplicate cannot surface a visible warning, and (b) a legitimate
session rotation deterministically triggers `session_sync`.

Verification from `app/` during implementation:

```bash
export PUB_CACHE=~/projects/remote_pi/.pub-cache
../.tools/flutter/bin/flutter test test/data/sync/session_gate_test.dart \
  test/data/sync/sync_service_test.dart
../.tools/flutter/bin/flutter analyze
```

No pi-extension test is required because its fail-closed route and wire shape
remain unchanged; its existing `session_gate.test.ts` continues to prove stale
commands are rejected before SDK delivery.

## Implementation order

1. Update `SyncService` and add both app regression tests in the same stride.
2. Refine `PROTOCOL.md` to the verified current contract.
3. Run targeted Flutter tests and `flutter analyze`.

## Risks

- **Metadata last-writer churn remains possible with duplicate Pis.** This
  design prevents a misleading warning and hydrates whichever session room
  metadata declares canonical; it does not solve duplicate-process targeting.
  That topology problem remains outside this story and must not be hidden by
  error-payload adoption.
- **Duplicate eager syncs.** `_onlineActivated` already schedules a 200 ms sync.
  The rotation path reuses `_pendingSyncRequest`; tests should assert the new
  session is synced without over-constraining incidental initial-sync counts.
  If implementation observes duplicate rotation syncs, dedupe through the
  existing latch rather than adding another boolean/timer.
- **Pending row ownership across replacement.** Activation intentionally
  cancels old-session timers and partitions transcript boxes. This story does
  not migrate an optimistically submitted old-session row into the new
  session; its guarantee is warning tolerance plus authoritative resync, not
  cross-session resend.

## Design completion

Single-stride app implementation; no child stories spawned. The story is ready
for `implement-orchestrator` at `stage: implementing`.

## Implementation notes

- Files changed:
  - `app/lib/data/sync/sync_service.dart` — two edits: (1) `_onRoomsChanged`
    arms `_pendingSyncRequest = true` before `activate(...)` on a canonical
    session-id rotation, so the newly bound session deterministically receives
    `session_sync` (the legitimate re-sync path); (2) the `ErrorMessage` arm
    breaks early on `code == 'session_mismatch'` — it is a convergence/control
    signal, never transcript content, so no `⚠` row is rendered. Other error
    codes (`internal_error`, `unknown_peer`, `delivery_pending`, future codes)
    retain the existing visible/revoked/pending behavior unchanged.
  - `app/test/data/sync/sync_service_test.dart` — added a `session_mismatch
    tolerance` group with 3 regression tests: (1) foreign duplicate-Pi
    mismatch reply dropped without a warning row (proves the existing inbound
    `SessionGate` catches it — confirmed by the `[session-gate] drop` debug
    line); (2) accepted current-session mismatch reply (the narrow metadata-
    rebound race window) also renders no warning row; (3) canonical room-
    metadata session rotation triggers `session_sync` for the new session id,
    never targeting the stale old id.
  - `PROTOCOL.md` — refined the `session_mismatch` error-code semantics: the
    Pi rejects fail-closed and returns its current `session_id`; the app treats
    the reply as a convergence/control signal (not visible transcript content);
    canonical room/session metadata — not the error payload — drives rebind +
    `session_sync`.
- Wire-shape decision: **app-side only**. The extension's fail-closed
  rejection and wire shape are unchanged; no pi-extension or relay change.
  The fix reuses the app's existing `SessionGate` (single source of truth for
  inbound session filtering) and the existing `_pendingSyncRequest` latch
  (single source of truth for deferred sync) — no new state machine.
- Discrepancies from design: none.
- Verification: `flutter analyze` clean; `flutter test
  test/data/sync/sync_service_test.dart test/data/sync/session_gate_test.dart`
  → 80/80 passed (77 existing + 3 new); the existing `internal_error` visible-
  warning test still passes (suppression cannot broaden).
