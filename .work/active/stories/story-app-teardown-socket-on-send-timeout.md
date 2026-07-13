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

## Design (locked in 2026-07-13) — REVISED after implementation attempt

> **Blocker (2026-07-13).** The implementation attempt uncovered a real
> conflict with a deliberate, tested recovery semantic. The premise that
> "tear down on every `send_timeout`" is safe is **wrong** as stated. The
> story is back at `stage: drafting` pending a design decision (below).

### The conflict: `send_timeout` is a SOFT, recoverable failure by design

The transcript-event-log epic
(`epic-bold-transcript-event-log-hydration-replay-step-2`, app-v1.2.0,
`c567ab3`) explicitly built and tested a **late-confirmation** path: a
message that hit `send_timeout` can still be **confirmed** by a later
`SessionHistory` replay (or `UserInput` echo), flipping the row from
`failed` → `confirmed`. The rationale (from that story, line 78): "Pending
timeouts become `UserMessageFailed` events; a later `UserMessageConfirmed`
from replay wins in projection and suppresses stale failure UI." This is
*exactly* the original half-open symptom's recovery: a message that arrives
minutes late gets reconciled to "confirmed" instead of leaving a stale
failure.

Tearing down the socket on `send_timeout` severs the channel that
**same-connection** late frames arrive on. `_onStatus` cancels `_msgSub` on
any non-online status (`sync_service.dart:590`), so after teardown emits
`StatusRetrying`, a late `SessionHistory`/`UserInput` pushed on the old
channel is dropped.

### What the implementation attempt broke

The test `late authoritative history replay after timeout confirms and
removes failure` (`sync_service_test.dart:1944`) failed: after `send_timeout`,
a `SessionHistory` push no longer confirms the row (stays `failed`). Its
sibling `late authoritative echo after timeout confirms and removes failure`
(`:1907`) has a weaker assertion (`.pending, isFalse` rather than
`.status == confirmed`) that **masks** the same breakage — a latent test-
integrity gap, not a reason to dismiss the finding.

### Why the conflict is real, not a test artifact

In **production**, late-confirmation works *across* a reconnect: teardown →
reconnect → `_onlineActivated` → `requestSync` → `SessionSync` → Pi responds
with `SessionHistory` → `_replayHistory` confirms the timed-out message. So
the recovery isn't broken in production — but the teardown adds **churn and
false positives** when the Pi is genuinely slow (socket fine, echo delayed
beyond 20s): a healthy socket gets torn down, and same-connection late
frames get dropped until reconnect.

`send_timeout` alone **cannot distinguish** "half-open dead socket" (the
capture's test 4) from "Pi slow but socket alive" (the late-confirmation
tests). Both present as "no echo in 20s."

### The deeper finding: option 1 + late-confirmation may already fix the
### user symptom

Re-examining what option 2 actually adds: option 1 (gate `sendMessage` on
`isRoomLive`) already prevents sends into a socket *proven* dead (3 missed
pongs). The window option 2 closes is `send_timeout` firing *before* 3
missed pongs (test 4: sent 00:08:10, timeout 00:08:30, room-offline not
until 00:09:15). In that window the message WAS written to the dead buffer
— but **late-confirmation already reconciles it**: when the dead buffer
flushes on reconnect (minutes late), `requestSync` → `SessionHistory`
confirms the row. The user sees a temporary `send_timeout` badge that flips
to delivered. The message is not lost; the failure is not stale.

So option 2's marginal benefit is **sooner teardown so the *next* send
doesn't hit the same dead buffer** — but option 1 already catches the next
send once the room flips offline (test 5 in the capture was held pending by
option 1). The window where a second send walks into a still-"live" dead
socket is narrow (the 45s between `send_timeout` and `ping_missed_room_offline`
in the capture), and even then late-confirmation reconciles it.

## Design decision needed (the question for the operator)

Given the above, the options are:

1. **Drop option 2.** Option 1 + late-confirmation already fix the
   user-visible symptom (message loss + stale failure). Option 2's marginal
   benefit (narrower dead-buffer window) doesn't justify the churn and the
   false-positive teardowns when the Pi is slow. **Close this story as
   superseded by the option-1 + late-confirmation analysis.**

2. **Corroborated teardown.** Tear down on `send_timeout` ONLY when there's
   independent dead-socket evidence — e.g. the room is *also* not live
   (option 1's signal), or a second consecutive `send_timeout`. But "room
   not live" is the case option 1 already handles (holds pending), so this
   reduces to: tear down when `send_timeout` fires AND `isRoomLive` is false
   — which is redundant with option 1's held-pending path (the message was
   never written to the channel, so there's no dead buffer to tear down
   for). A second-consecutive-timeout gate is plausible but adds state and
   still churns on genuine double-slowness.

3. **Tear down + update the late-confirmation tests to model reconnect.**
   Accept the churn, update the two late-confirmation tests to reconnect
   before pushing the late frame (models the production post-teardown
   flow). This is the original design, but it accepts false-positive
   teardowns when the Pi is slow and weakens the same-connection recovery.

**Lean: option 1 (drop).** The analysis shows option 1 + late-confirmation
already fix the symptom this story was meant to close. Forcing teardown
through (option 3) trades a narrow dead-buffer window for churn and
false positives, and weakens a deliberate recovery semantic. But this is
an operator decision because it reverses the story's original premise.

### What NOT to do (unchanged)

- Do **not** re-attempt the timed-out message automatically as part of this
  story. That's option 4 (re-attempt on reconnect), filed separately.
- Do **not** re-evaluate the Plan-18 decoupling itself in this story. The
  finding that Plan-18's rationale is obsolete (below) stands and is
  recorded for a future story.

### Plan-18 obsolescence note (for a future story — UNCHANGED, still valid)

The Plan-18 decoupling comment (`connection_manager.dart:1286-1304`) states
its rationale: tearing down on missed pongs caused `room_already_open`
reconnect failures because the relay held the slot on half-open TCP. That
rationale is now obsolete — `room_already_open` is gone from relay source,
and same-device supersession (`story-relay-close-same-device-duplicate-auth`,
v0.1.0) actively closes the prior conn on re-auth. A future story could
re-evaluate whether 3-missed-pong should now tear down the WS too (re-coupling
Pi-liveness to WS-liveness). This story does not do that. The finding is
recorded here for provenance regardless of how the option-2 decision resolves.

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
