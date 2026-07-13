---
id: story-app-teardown-socket-on-send-timeout
kind: story
stage: implementing
tags: [app, bug, lifecycle, transport]
parent: feature-reconnect-reproduction
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-13
updated: 2026-07-13
follow_up_of: story-app-half-open-socket-swallows-sends-arrives-late
---

# Tear down the suspect socket on `send_timeout` (half-open fix, option 2)

## Brief

Direct follow-up to `story-app-half-open-socket-swallows-sends-arrives-late`
(option 1, shipped `6d64556`). Option 1 gates `sendMessage` on room liveness
(`_conn.isRoomLive`) so a send into a socket the app has *proven* unreachable
(3 missed pongs → `_markActiveRoomOffline`) is held pending instead of
vanishing into a dead send buffer. But option 1 leaves a **window**: the
20s echo timeout can fire *before* 3 missed pongs do. In the dispositive
capture (ring `e4f-11f1`), test 4 was sent at `00:08:10` and `send_timeout`
fired at `00:08:30`, but `ping_missed_room_offline` didn't fire until
`00:09:15` — 45s after the timeout. During that window the dead socket stays
`StatusOnline` and the next send walks back into it.

Option 2 closes that window: **the 20s echo timeout is itself a dead-socket
signal.** When `send_timeout` fires, the round-trip is broken; rather than
declaring the message failed while leaving the dead socket in `StatusOnline`,
force a reconnect so the *next* send doesn't hit the same dead buffer.

## The central design question (and the answer found in code)

Option 2 was flagged as the "most consequential follow-up" in the option-1
review because it risks reintroducing the failure Plan-18 was built to avoid:
**`room_already_open` reconnect failures.** The Plan-18 decoupling comment
(`connection_manager.dart:1286-1304`) states that tearing down on missed
pongs caused the app to sit permanently offline, because the relay held the
slot until its own `sink.send` errored (minutes on half-open TCP), so every
reconnect hit `room_already_open`.

**Verification (2026-07-13, against current code):** that rationale is
**obsolete.**

1. `room_already_open` appears **nowhere** in current relay source. The only
   occurrence in the whole repo is the Plan-18 comment in the app. (It was
   real once — `git log -S` shows it in relay history at `0956a74`/`3737c11` —
   but it has since been removed.)
2. The relay now **actively closes the prior same-device conn on re-auth**
   (`story-relay-close-same-device-duplicate-auth`, shipped v0.1.0, `5741775`,
   2026-07-10). `ConnectionRegistry::insert()` drops the old conn's `tx`
   (`connections.rs:84-95`), so the old `handle_peer` loop's `rx.recv()`
   returns `None` → the old socket tears down immediately. That story's brief
   explicitly fixes "recovery latency gated by ping timeout rather than by
   the reconnect itself" — the exact half-open-TCP problem Plan-18 worked
   around.
3. Timeline: Plan-18 landed **2026-05-22** (`7767421`); supersession landed
   **2026-07-10** (`5741775`). Plan-18 was correct when written; the relay
   change that made it unnecessary shipped 7 weeks later.

So the `room_already_open` failure mode Plan-18 defended against no longer
exists. A `send_timeout`-triggered teardown now reconnects cleanly: the relay
closes the old slot on the new auth, and the app's `_onChannelLost` →
`_scheduleRetry` → `_connect` path succeeds.

> **Caveat to verify in design.** This is grounded in code inspection +
> git history, not a live reproduction of a `send_timeout`-triggered
> reconnect. The design pass must confirm there is no *other* path that
> rejects a same-device re-auth (e.g. a rate limit, or a relay-side
> "connection storm" guard) before relying on it. The lesson from the
> half-open investigation applies: a static trace that "explains" the
> behavior can still be wrong about the mechanism — verify the actual path.

## Design (locked in 2026-07-13)

### The corroborating signal already exists: `delivery_pending`

The open question was unconditional-vs-corroborated teardown. Resolved by
reading the echo path: the protocol already distinguishes "Pi never
acknowledged" from "Pi acknowledged but is slow."

- `_onSendTimeout` (20s, `sync_service.dart:381`) fires when the Pi sent
  **no acknowledgment at all** — neither an echo nor a `delivery_pending`.
  The message never round-tripped → **dead socket → tear down.**
- `_onDeliveryPendingTimeout` (60s, `sync_service.dart:404`) fires only
  after the Pi sent an `ErrorMessage` with `code: 'delivery_pending'`
  (`sync_service.dart:987`), which re-arms the timer to 60s. That frame
  *did* round-trip (app→relay→Pi→relay→app), so the socket is proven alive
  and the Pi is just slow → **do NOT tear down.**

So the decision is: **tear down on the 20s `_onSendTimeout` path only;
never on the 60s `_onDeliveryPendingTimeout` path.** The corroboration is
already wired into the protocol — no new signal needed. This avoids
spurious reconnects when the Pi is genuinely busy (the 60s path proves the
socket is healthy) while catching the dead-socket case the 20s path
represents.

### Where the teardown hooks in

`_onSendTimeout` (`sync_service.dart:381`) currently calls `_failPendingSend`
which marks the row failed and unwinds turn state. Option 2 adds: after
failing the message, **signal the transport to tear down the suspect
socket.** The message still fails visibly (the `send_timeout` badge is
honest — the round-trip did break); the teardown is about the *next* send.

The seam is `ConnectionManager` (the transport owns the socket lifecycle,
not `SyncService`). `SyncService` holds `final ConnectionManager _conn`
(`sync_service.dart:37`). `ConnectionManager` has the private
`_onChannelLost` (`connection_manager.dart:1228`) and a
`@visibleForTesting debugSimulateChannelLost` (`:1260`), but **no public
force-reconnect**. Add one:

```dart
/// Force-teardown the active channel and enter the retry path. Used when a
/// higher layer (SyncService send-timeout) has independent evidence the
/// socket is dead even though WS-liveness hasn't surfaced it yet. Safe now
/// that the relay closes the prior same-device conn on re-auth (v0.1.0,
/// story-relay-close-same-device-duplicate-auth) — the reconnect won't hit
/// `room_already_open` (the failure Plan-18's decoupling worked around; that
/// rationale is obsolete, see the design-question section above).
void forceReconnectForSuspectedDeadSocket() {
  final peer = _activePeer;
  final ch = (_status is StatusOnline) ? (_status as StatusOnline).channel : null;
  if (peer == null || ch == null) return; // nothing live to tear down
  _onChannelLost(peer, ch);
}
```

`_onChannelLost` already does the right thing: cancels ping, fires
`connChannelLost stale:false`, calls `_scheduleRetry` → `_connect`. The
relay's same-device supersession closes the old slot on the new auth, so
the reconnect succeeds cleanly (verified: no `room_already_open` in relay
source; no auth-side rate limit; the only `Close` on a new conn is
auth-failure at `peer.rs:90`, which won't happen on a legitimate
reconnect).

In `SyncService._onSendTimeout`, after `_failPendingSend`:

```dart
void _onSendTimeout(String id, RemoteSessionRef expectedRef) {
  _failPendingSend(
    id,
    code: 'send_timeout',
    message: 'Message was not confirmed by the Pi. It may not have been delivered.',
    debugDetail: 'no echo in ${pendingSendTimeout.inSeconds}s',
    expectedRef: expectedRef,
  );
  // Half-open socket teardown (option 2): a 20s send_timeout with no
  // delivery_pending means the message never round-tripped — the socket's
  // app→relay direction is dead even though WS-liveness hasn't surfaced it.
  // Tear down so the next send goes to a fresh connection instead of the
  // same dead buffer. NOT called from _onDeliveryPendingTimeout (60s): that
  // path means delivery_pending round-tripped, so the socket is alive.
  _conn.forceReconnectForSuspectedDeadSocket();
}
```

### What NOT to do

- Do **not** re-attempt the timed-out message automatically as part of this
  story. That's option 4 (re-attempt on reconnect), filed separately. Option
  2 is purely "tear down so the next send is healthy." Mixing them couples
  two concerns and makes the test surface ambiguous. The timed-out message
  stays failed; if the operator wants auto-retry, that's option 4.
- Do **not** tear down from `_onDeliveryPendingTimeout` (the 60s path). That
  path fires only after `delivery_pending` round-tripped, proving the socket
  is alive.
- Do **not** re-evaluate the Plan-18 decoupling itself in this story (should
  3-missed-pong now tear down the WS too?). That's a larger question; this
  story only adds the `send_timeout` teardown. The finding that Plan-18's
  rationale is obsolete is recorded in this story body for a future story
  to pick up.

### Test plan

A failing test reproducing the window option 1 does *not* cover: send a
message into a socket that is `StatusOnline` AND whose room is still live
(`isRoomLive` true — the 3-missed-pong threshold hasn't fired) → advance the
20s `send_timeout` → assert the transport tears down the socket
(`StatusRetrying` emitted / `connChannelLost` fired), not just the message
row failing while `StatusOnline` persists.

A second test asserts the 60s path does NOT tear down: deliver a
`delivery_pending` ErrorMessage for the pending id → advance to the 60s
`_onDeliveryPendingTimeout` → assert the message fails but the transport
stays `StatusOnline` (no `StatusRetrying`).

### Plan-18 obsolescence note (for a future story)

The Plan-18 decoupling comment (`connection_manager.dart:1286-1304`) states
its rationale: tearing down on missed pongs caused `room_already_open`
reconnect failures because the relay held the slot on half-open TCP. That
rationale is now obsolete — `room_already_open` is gone from relay source,
and same-device supersession (`story-relay-close-same-device-duplicate-auth`,
v0.1.0) actively closes the prior conn on re-auth. A future story could
re-evaluate whether 3-missed-pong should now tear down the WS too (re-coupling
Pi-liveness to WS-liveness), which would make option 2's send-timeout
teardown redundant for the post-75s case. This story does not do that — it
only closes the pre-75s window. Filed as a follow-up consideration in the
story body, not a separate item (acceptable for a single-stride fix).

## Acceptance

- When `send_timeout` fires on a socket still in `StatusOnline`, the
  transport tears down the suspect socket and enters the retry path
  (`StatusRetrying`), so the next send goes to a fresh connection rather
  than the same dead buffer.
- The teardown does not reintroduce `room_already_open`-style permanent
  offline (verified: the relay's same-device supersession closes the old
  slot on re-auth).
- A failing test reproduces the pre-3-missed-pong window and asserts the
  teardown.
- Full app suite green; analyzer clean.

## Out of scope

- Option 3 (tighten WS `pingInterval` 45s→15–20s) — secondary; helps the
  `onDone` path detect a fully-dead socket sooner. Separate.
- Option 4 (re-attempt timed-out messages on reconnect) — UX safety net;
  separate story.
- Re-evaluating the Plan-18 decoupling itself (should 3-missed-pong now tear
  down the WS too, since `room_already_open` is gone?). That's a larger
  question; this story only adds the `send_timeout` teardown. But the
  finding that Plan-18's rationale is obsolete should be recorded in the
  Plan-18 comment / a durable note so a future story can pick up the
  decoupling re-evaluation.

## References

- `app/lib/data/sync/sync_service.dart:381` — `_onSendTimeout` (hook point).
- `app/lib/data/sync/sync_service.dart:376` — `_armSendTimeout` / `pendingSendTimeout` (20s).
- `app/lib/data/transport/connection_manager.dart:1228` — `_onChannelLost` (teardown path).
- `app/lib/data/transport/connection_manager.dart:1286-1326` — Plan-18 decoupling block (rationale now obsolete — see Design).
- `app/lib/data/transport/connection_manager.dart:921` — `isRoomLive` (option 1's gate; still true in the window this story closes).
- `relay/src/peers/connections.rs:84-95` — same-device supersession (closes prior conn on re-auth).
- `.work/releases/v0.1.0/story-relay-close-same-device-duplicate-auth.md` — supersession story (the change that obsoleted Plan-18's rationale).
- `story-app-half-open-socket-swallows-sends-arrives-late.md` — option 1 (shipped); options 2–4 filed in its body.
