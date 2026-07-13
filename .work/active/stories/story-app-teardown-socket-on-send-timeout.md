---
id: story-app-teardown-socket-on-send-timeout
kind: story
stage: drafting
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

## Design (to lock in during the design pass)

### Where the teardown hooks in

`_onSendTimeout` (`sync_service.dart:381`) currently calls `_failPendingSend`
which marks the row failed and unwinds turn state. Option 2 adds: after
failing the message, **signal the transport to tear down the suspect
socket.** The message still fails visibly (the `send_timeout` badge is
honest — the round-trip did break); the teardown is about the *next* send.

The seam is `ConnectionManager` (the transport owns the socket lifecycle,
not `SyncService`). `SyncService` holds `_conn` (a `ConnectionManager`); it
needs a method like `_conn.forceReconnectForSuspectedDeadSocket()` that
calls `_onChannelLost` on the active channel. `_onChannelLost`
(`connection_manager.dart:1228`) already does the right thing: cancels ping,
fires `connChannelLost`, calls `_scheduleRetry` → `_connect`.

### What NOT to do

- Do **not** re-attempt the timed-out message automatically as part of this
  story. That's option 4 (re-attempt on reconnect), filed separately. Option
  2 is purely "tear down so the next send is healthy." Mixing them couples
  two concerns and makes the test surface ambiguous. The timed-out message
  stays failed; if the operator wants auto-retry, that's option 4.
- Do **not** tear down on *every* `send_timeout`. A `send_timeout` can also
  fire when the Pi is genuinely busy (slow echo) but the socket is healthy.
  The design must decide: tear down unconditionally (simplest, may cause
  occasional unnecessary reconnects when the Pi is just slow), or only when
  there's corroborating signal (e.g. room already marked offline, or a
  second consecutive timeout). **Lean: tear down unconditionally** — a
  20s echo miss is a strong enough signal, and a clean reconnect is cheap
  now that supersession exists. But confirm in design.

### Test plan

A failing test reproducing the window: send a message into a socket whose
app→relay direction is dead but whose room is *not yet* marked offline (the
3-missed-pong threshold hasn't fired) → `send_timeout` fires → assert the
transport tears down the socket (`_onChannelLost` / `StatusRetrying`
emitted), not just the message row failing while `StatusOnline` persists.

This is the case option 1 does *not* cover (option 1 only gates on
`isRoomLive`, which is still true in this window).

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
