---
id: story-app-teardown-socket-on-send-timeout
status: superseded
superseded_by: story-app-half-open-socket-swallows-sends-arrives-late (option 1)
created: 2026-07-13
updated: 2026-07-13
tags: [app, bug, lifecycle, transport]
status: parked
follow_up_of: story-app-half-open-socket-swallows-sends-arrives-late
---

# ⏸ PARKED — Tear down the suspect socket on `send_timeout` (half-open fix, option 2)

> ## STATUS: PARKED — revisit or retire
>
> **Not ready to implement. Do NOT pick this up as active work without
> reading this whole block.** The original premise (tear down on every
> `send_timeout`) was disproven by an implementation attempt on 2026-07-13.
>
> **TL;DR.** This was option 2 of the half-open socket fix (option 1 shipped
> `8a0d43c`). The design pass found Plan-18's rationale is obsolete (good —
> see finding below), so teardown *looked* safe. But the implementation
> attempt broke a deliberate, tested recovery semantic: `send_timeout` is a
> **soft, recoverable** failure by design, and tearing down the socket severs
> the channel that late confirmations arrive on. On re-examination, **option 1
> + the existing late-confirmation path already fix the user symptom** this
> story was meant to close. Option 2's marginal benefit (a narrower dead-buffer
> window) doesn't justify the churn and false-positive teardowns.
>
> **Two paths forward (operator decision, deferred):**
>
> 1. **Retire it.** Mark SUPERSEDED — option 1 + late-confirmation already
>    fix the symptom. *(Current lean.)*
> 2. **Revisit** only if a future capture shows the narrow pre-3-missed-pong
>    window (send_timeout fires while room still live) causing a *user-visible*
>    problem that late-confirmation doesn't already reconcile. If so, the
>    viable design is **corroborated teardown** (tear down only with
>    independent dead-socket evidence), NOT unconditional — see the design
>    analysis below.
>
> **Two durable findings to carry forward regardless of the decision** (these
> do NOT depend on resolving this story):
>
> - **Plan-18's rationale is obsolete.** `room_already_open` is gone from
>   relay source; same-device supersession (`story-relay-close-same-device-
>   duplicate-auth`, v0.1.0, `9f6682c`) actively closes the prior conn on
>   re-auth. Plan-18 (2026-05-22) was correct when written; the relay change
>   that obsoleted it landed 2026-07-10. A future story could re-evaluate
>   whether 3-missed-pong should now tear down the WS too (re-coupling
>   Pi-liveness to WS-liveness). That is the more promising follow-up than
>   this story.
> - **`late authoritative echo after timeout confirms` has a weak assertion**
>   (`.pending, isFalse` rather than `.status == confirmed`) that masks the
>   breakage this story's implementation caused. A latent test-integrity gap
>   worth fixing independently — its sibling `late authoritative history
>   replay` has the strong assertion that correctly caught it.
>
> **Why parked, not retired now:** the operator chose to keep the full
> analysis on ice with a clear signal rather than close it immediately, so a
> future agent (or operator) can retire it informedly or revive it if new
> evidence appears. The analysis below is the load-bearing content; the
> status block above is the routing signal.

---

## Brief (original premise — since challenged)

Direct follow-up to `story-app-half-open-socket-swallows-sends-arrives-late`
(option 1, shipped `8a0d43c`). Option 1 gates `sendMessage` on room liveness
(`_conn.isRoomLive`) so a send into a socket the app has *proven* unreachable
(3 missed pongs → `_markActiveRoomOffline`) is held pending instead of
vanishing into a dead send buffer. But option 1 leaves a **window**: the
20s echo timeout can fire *before* 3 missed pongs do. In the dispositive
capture (ring `e4f-11f1`), test 4 was sent at `00:08:10` and `send_timeout`
fired at `00:08:30`, but `ping_missed_room_offline` didn't fire until
`00:09:15` — 45s after the timeout. During that window the dead socket stays
`StatusOnline` and the next send walks back into it.

Option 2 was meant to close that window: **the 20s echo timeout is itself a
dead-socket signal.** When `send_timeout` fires, force a reconnect so the
*next* send doesn't hit the same dead buffer. **This premise is wrong as
stated** — see the design analysis.

## Finding 1 (durable): Plan-18's rationale is obsolete

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
   (`story-relay-close-same-device-duplicate-auth`, shipped v0.1.0, `9f6682c`,
   2026-07-10). `ConnectionRegistry::insert()` drops the old conn's `tx`
   (`connections.rs:84-95`), so the old `handle_peer` loop's `rx.recv()`
   returns `None` → the old socket tears down immediately. That story's brief
   explicitly fixes "recovery latency gated by ping timeout rather than by
   the reconnect itself" — the exact half-open-TCP problem Plan-18 worked
   around.
3. Timeline: Plan-18 landed **2026-05-22** (`7767421`); supersession landed
   **2026-07-10** (`9f6682c`). Plan-18 was correct when written; the relay
   change that made it unnecessary shipped 7 weeks later.

So the `room_already_open` failure mode Plan-18 defended against no longer
exists. A `send_timeout`-triggered teardown *would* reconnect cleanly. **This
finding stands regardless of the option-2 decision** and is the more
promising follow-up (re-evaluate the Plan-18 decoupling itself).

## Finding 2 (the blocker): `send_timeout` is a SOFT, recoverable failure

The implementation attempt (code reverted; only this analysis committed)
uncovered the real conflict. The transcript-event-log epic
(`epic-bold-transcript-event-log-hydration-replay-step-2`, app-v1.2.0,
`ed2d643`) explicitly built and tested a **late-confirmation** path: a
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
integrity gap (finding 3 below), not a reason to dismiss the finding.

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

## Finding 3 (durable): option 1 + late-confirmation may already fix the symptom

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

## The three options (if revisited)

1. **Retire (drop).** Option 1 + late-confirmation already fix the
   user-visible symptom. Option 2's marginal benefit doesn't justify the
   churn and false-positive teardowns. *(Current lean.)*
2. **Corroborated teardown.** Tear down on `send_timeout` ONLY with
   independent dead-socket evidence — e.g. room *also* not live, or a second
   consecutive `send_timeout`. But "room not live" is the case option 1
   already handles (holds pending, never written to the channel), so this
   reduces to redundancy. A second-consecutive-timeout gate is plausible but
   adds state and still churns on genuine double-slowness.
3. **Tear down + update the late-confirmation tests to model reconnect.**
   Accepts churn and false-positive teardowns when the Pi is slow; weakens
   the same-connection recovery.

## References

- `app/lib/data/sync/sync_service.dart:381` — `_onSendTimeout` (the would-be hook point).
- `app/lib/data/sync/sync_service.dart:376` — `_armSendTimeout` / `pendingSendTimeout` (20s).
- `app/lib/data/sync/sync_service.dart:590` — `_onStatus` cancels `_msgSub` on non-online (the breakage mechanism).
- `app/lib/data/sync/sync_service.dart:625` — `_onlineActivated` → `requestSync` (why late-confirmation works across reconnect).
- `app/lib/data/transport/connection_manager.dart:1228` — `_onChannelLost` (the teardown path).
- `app/lib/data/transport/connection_manager.dart:1286-1326` — Plan-18 decoupling block (rationale obsolete — finding 1).
- `app/lib/data/transport/connection_manager.dart:921` — `isRoomLive` (option 1's gate).
- `relay/src/peers/connections.rs:84-95` — same-device supersession (closes prior conn on re-auth).
- `.work/releases/v0.1.0/story-relay-close-same-device-duplicate-auth.md` — supersession story (obsoleted Plan-18).
- `.work/releases/app-v1.2.0/epic-bold-transcript-event-log-hydration-replay-step-2.md` — late-confirmation design (the blocker).
- `app/test/data/sync/sync_service_test.dart:1907` — `late authoritative echo` (weak assertion; finding 2).
- `app/test/data/sync/sync_service_test.dart:1944` — `late authoritative history replay` (strong assertion; caught the breakage).
- `story-app-half-open-socket-swallows-sends-arrives-late.md` — option 1 (shipped); options 2–4 filed in its body.
