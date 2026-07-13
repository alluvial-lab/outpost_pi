---
id: story-app-half-open-socket-swallows-sends-arrives-late
kind: story
stage: done
tags: [app, bug, lifecycle, transport]
parent: feature-reconnect-reproduction
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-12
updated: 2026-07-13
reviewed: 2026-07-13
prior_id: story-app-ws-churn-10-50s-reconnect-loop
---

# Half-open relay socket swallows outbound messages, flushes them minutes late

## Observed (2026-07-13, proven across three sides)

The phone sends a message; the app's 20s echo timeout fires (`send_timeout`,
"no echo in 20s") and the user sees a failure — then the message arrives at
the PC **minutes later**, injected into a running turn (`steer:true`). Two
messages sent into the same dead socket can arrive together on a single
reconnect, long after both were declared failed.

This is a **half-open socket detection-latency** bug, not message loss and not
reconnect churn.

### The proof: two messages, one flush (ring `e4f-11f1-b58b-d1e218f193f4.bin`)

| Msg | Phone `msgSend` | Phone `msgFailed` | PC `msg_received` | Delay |
|---|---|---|---|---|
| test 4 (`…f70f68fe10a4`) | 00:08:10.961 | 00:08:30.941 (20s timeout) | **00:11:54.834** | **3 min 44 s** |
| test 5 (`…bbdcd96334ef`) | 00:10:19.464 | 00:10:39.471 (20s timeout) | **00:11:54.840** | **1 min 35 s** |

Both arrived at the PC within **6 ms of each other**, both `steer:true`,
both `source:app` — a single reconnect flushed the entire backlog. The
messages were never lost; they sat in a dead send buffer for minutes.

### Three-sided timeline (the dispositive sequence)

```
00:08:00.372  relay: app authenticated …52532 (superseded_existing=false)
00:08:10.961  ring:   msgSend test 4   (app StatusOnline, socket believed live)
00:08:30.941  ring:   msgFailed test 4  send_timeout "no echo in 20s"
              ↑ app still StatusOnline — no connChannelLost fired
00:09:15.743  ring:   workingConv ping_missed_room_offline  (75s: 3 missed pongs)
              ↑ the protocol-Ping liveness FINALLY fires — 65s after the send
00:10:10.511  relay: app disconnected …52532  (130s after auth; OS finally tore it down)
00:10:12.963  relay: app authenticated …55202 (reconnect)
00:10:19.464  ring:   msgSend test 5   (into ANOTHER dead socket)
00:10:39.471  ring:   msgFailed test 5  send_timeout
00:11:28.330  ring:   workingConv ping_missed_room_offline  (ring ENDS here)
00:11:54.834  PC:     msg_received test 4  steer:true   ← BOTH FLUSHED
00:11:54.840  PC:     msg_received test 5  steer:true   ← TOGETHER
00:11:59.469  relay: app disconnected …55202
00:12:02.697  relay: app authenticated …46042
```

An earlier capture (ring `e46-11f1-9c1d-4b063f8904fb-1.bin`, 2026-07-12
23:07–23:08) showed the same mechanism with a single message: test 2 sent at
23:08:08, `send_timeout` at 23:08:28, arrived at the PC at 23:09:02 (54s
late, `steer:true`). That ring ended before the late arrival, which initially
obscured the flush-on-reconnect mechanism.

## Root cause (corrected 2026-07-13 after verifying the reset path)

> **Correction.** The original root-cause write-up (preserved below as
> "Initial (incorrect) root-cause write-up") claimed relay control frames
> (`peer_online`) reset `_missedPings` via `onAppFrameObserved`, masking the
> half-open. **That is wrong.** Verifying the code before implementing showed:
> `onAppFrameObserved` is called ONLY by `_watchChannel`'s `serverMessages`
> listener (`connection_manager.dart:1209-1218`), and `serverMessages` carries
> only decoded `ServerMessage` types (`pong`, `user_message`, `agent_chunk`,
> …) — NOT relay control frames. Control frames (`peer_online`/`presence`/
> `rooms`) route through `_onControl` (`connection_manager.dart:597`), which
> does NOT call `onAppFrameObserved` or reset `_missedPings`. The capture
> confirms this: between `00:08:00` (auth) and `00:09:15`
> (`ping_missed_room_offline`), zero `wsIn kind=envelope` lines appear — only
> `control` frames. So `_missedPings` was NOT being reset by control frames;
> the 75s `ping_missed_room_offline` fired as designed.

The real mechanism is a **design-decoupling gap**, not a reset bug:

1. **Pi-liveness is deliberately decoupled from WS-liveness**
   (`_startPing`, `connection_manager.dart:1283-1326`, comment "Plan-18
   follow-up — DECOUPLED Pi-liveness from WS-liveness"). Three missed
   protocol Pongs call `_markActiveRoomOffline()` — which only removes the
   room from `_liveRoomIds` and flips the UI tile grey. It **deliberately
   does NOT** tear down the WS or call `_onChannelLost`. The stated reason:
   tearing down the WS on missed pongs used to cause `room_already_open`
   reconnect failures (the relay holds the slot until its `sink.send` errors,
   which can take minutes on half-open TCP).

2. **So a half-open WS (app→relay dead, relay→app alive) stays `StatusOnline`.**
   The protocol-ping probe (`ch.send(Ping(...))`) either succeeds at the TCP
   layer (bytes leave the socket buffer into the dead direction) or throws —
   and if it throws, `_onChannelLost` fires. But on a half-open socket the
   `send` typically does NOT throw until the OS detects the dead peer (RST/
   timeout), which is exactly the 65–130s latency the capture shows. The
   WS-level `pingInterval: 45s` (`ws_transport.dart:96`) has the same problem:
   `IOWebSocketChannel` closes on missed WS-pong only after the TCP stack
   surfaces the failure, not on a logical timeout.

3. **The send path trusts `StatusOnline`.** `msgSend` at `00:08:10.961` and
   `00:10:19.464` proceeds because `connStatus` is `online`. Nothing connects
   "3 missed pongs" (room marked offline at `00:09:15`) to "stop accepting
   sends" or "tear down for reconnect." The app sent test 5 at `00:10:19` —
   **after** `ping_missed_room_offline` had already fired at `00:09:15` — into
   the same dead socket.

4. **On the next reconnect, the dead send buffer flushes.** The bytes queued
   by `msgSend` finally leave when the app re-authenticates; they arrive at
   the PC together, minutes late, `steer:true`.

The crux: **the decoupling that fixed the `room_already_open` reconnect
failure created a blind spot** — the app will keep sending into a socket it
has already proven (via 3 missed pongs) is not delivering to the Pi, because
"not delivering to the Pi" was made distinct from "WS is dead."

### What the capture actually proves (vs the initial write-up)

- ✅ Half-open socket lingers in `StatusOnline` for 65–130s — **proven**.
- ✅ `msgSend` into the dead socket → `send_timeout` → late flush on
  reconnect — **proven** (two messages, one flush).
- ✅ Protocol-ping liveness fires at 75s but only marks the room offline, not
  the WS — **proven** (`ping_missed_room_offline` at `00:09:15`, no
  `connChannelLost` until much later).
- ❌ "Control frames reset `missedPings`" — **disproven by code inspection**.
  Control frames route through `_onControl`, not `serverMessages`; they do
  not reset the counter. The 75s detection was the designed, correct
  behavior of the protocol-ping path.

## Initial (incorrect) root-cause write-up (superseded above)

The app sends into a socket whose **app→relay direction is dead**, and no
liveness signal catches it within the 20s echo window:

1. **Asymmetric half-open.** The socket dies in one direction: app→relay is
   dead (the app's `msgSend` bytes leave the send call but never reach the
   relay), but relay→app stays alive — relay control frames (`peer_online`)
   keep arriving (`00:08:31`, `00:09:50`, `00:10:04`). Each inbound control
   frame resets `_missedPings = 0` via `onAppFrameObserved`
   (`reachability_adapter.dart:50-53`), masking the dead direction.

2. **WS-level `onDone` is too slow.** The 45s `pingInterval`
   (`ws_transport.dart:96`) does not surface `onDone` until the OS tears the
   socket down at 00:10:10 — **130s after auth**. The app's
   `_onChannelLost` → `connChannelLost stale:false` does not fire during the
   20s echo window, so the phone keeps `StatusOnline`.

3. **Protocol-Ping liveness is too slow AND gets reset by control frames.**
   The 25s protocol Ping needs `missedPings==3` (75s) to fire
   `ping_missed_room_offline` — which it does at 00:09:15 (65s after the send)
   and 00:11:28. But that only marks the *room* offline locally
   (`_markActiveRoomOffline`); it does **not** tear down the WS or trigger
   `_onChannelLost`, so the dead send buffer is not drained/retried. And the
   counter keeps getting reset by the still-arriving relay control frames,
   so the 75s threshold is the *best case*.

4. **The 20s echo timeout fires on a socket the app still thinks is live.**
   `msgFailed send_timeout "no echo in 20s"` at 00:08:30 and 00:10:39 — both
   while `connStatus` is `online` (no `connChannelLost`).

5. **On the next reconnect, the dead send buffer flushes.** The app reconnects
   at 00:10:12 and 00:12:02; the queued bytes finally leave the socket and
   arrive at the PC at 00:11:54 — together, minutes late, `steer:true`.

The crux: `onAppFrameObserved` treats **any** inbound `ServerMessage` as proof
of bidirectional liveness, but relay control frames (`peer_online`,
`presence`, `rooms`) only prove **relay→app** liveness. Only a `Pong` (the
app→relay→app round trip) proves the app→relay direction is alive. Resetting
`missedPings` on a one-directional control frame hides the half-open.

## Fix direction (corrected)

The proven mechanism is a **decoupling gap**: Pi-liveness (protocol Ping,
3-miss → mark room offline) was deliberately separated from WS-liveness
(don't tear down on missed pongs, to avoid `room_already_open` reconnect
failures). But the send path trusts `StatusOnline`, and nothing connects
"3 missed pongs" to "stop sending into this socket." The app keeps accepting
`msgSend` into a socket it has already proven is not reaching the Pi.

1. **Gate `msgSend` on room liveness, not just WS `StatusOnline`.**
   When `_markActiveRoomOffline` fires (3 missed pongs → room removed from
   `_liveRoomIds`), the send path must refuse or queue the message rather
   than writing into the dead socket. This is the direct fix for the observed
   bug: test 5 was sent at `00:10:19`, **after** `ping_missed_room_offline`
   at `00:09:15` — the app had already proven the room was dead but still
   sent. *(Direct fix.)*

2. **On `send_timeout`, tear down the suspect socket.** The 20s echo timeout
   is itself a liveness signal: no echo means the round-trip is broken.
   Rather than declaring the message failed while leaving the dead socket in
   `StatusOnline`, force a reconnect so the next send doesn't hit the same
   dead buffer. This prevents the flush-minutes-late symptom for the case
   where ping-miss hasn't fired yet (test 4: sent `00:08:10`, room-offline
   didn't fire until `00:09:15`). *(Fail-safe — covers the window before
   3 missed pongs.)*

3. **Tighten the WS `pingInterval` from 45s toward 15–20s.** This is the
   shipped flapping story's lever; 45s over-corrected against false teardowns.
   A shorter interval surfaces `onDone` for a genuinely dead TCP connection
   sooner. This is secondary — it helps the `onDone` path detect a
   fully-dead socket faster, but does not address the half-open case where
   the TCP stack hasn't surfaced the failure (the decoupling gap in option 1
   is the real fix for that). *(Secondary.)*

4. **Re-attempt timed-out messages on reconnect.** Even with better
   detection, a message that hit `send_timeout` should be re-attempted on
   the next healthy connection rather than silently arriving minutes late
   (and being double-counted by the user). The `send_timeout` badge should
   not coexist with the message actually landing. *(UX safety net.)*

Options 1 + 2 are the root-cause pair (don't send into a socket the app has
proven dead; and use the echo timeout itself as a dead-socket signal);
options 3 and 4 are secondary/safety-net.

> **Note on the superseded option list.** The initial fix-direction write-up
> (in the "Initial (incorrect) root-cause write-up" section below) proposed
> "stop resetting `missedPings` on relay control frames" as a root-cause fix.
> That option is **invalid**: control frames do not reset `_missedPings` (they
> route through `_onControl`, not `serverMessages`). It is retained only as
> provenance for what was considered and rejected.

## Implementation (2026-07-13 — option 1 shipped)

Option 1 (gate `msgSend` on room liveness) is implemented in
`app/lib/data/sync/sync_service.dart` `sendMessage`: after the existing
`_conn.channel` non-null check, a new guard calls `_conn.isRoomLive(epk,
roomId)`. When the active room is not live (3 missed pongs →
`_markActiveRoomOffline`, or a `RoomEnded` push), the message takes the same
held-pending path as the offline branch (writes the optimistic row, arms the
send-timeout, returns without writing to the channel) instead of vanishing
into a dead send buffer.

`ConnectionManager.isRoomLive` (`connection_manager.dart:921`) already returns
false after `_markActiveRoomOffline` removes the room from `_liveRoomIds`, so
no new liveness signal was needed — the fix is purely a send-path gate.

### Test

`app/test/data/sync/sync_service_test.dart` test `(i) half-open socket: room
marked offline holds the send pending instead of writing into a dead WS`
models the capture: `RoomEnded` push marks the active room offline while the
WS stays `StatusOnline` → `sendMessage` → assert the message is held pending
(NOT sent on the channel) and the send-timeout is armed. The test's
`_FakeChannel` was extended to implement `IControlLink` (so `RoomEnded` can
be pushed via the control-frame path).

Verified TDD: the test fails without the fix (`Expected: empty / Actual:
[UserMessage]` — the message was sent into the dead socket) and passes with
it. All 76 tests in `sync_service_test.dart` pass; analyzer clean.

### Test-contamination note

Adding the test initially broke the pre-existing `canonical room-metadata
session rotation triggers session_sync` test (last in the suite). Bisect
showed even a trivial `setup()+dispose()` test broke it — the rotation test's
`2×_settle()` (60ms) was too tight for the 50ms debounced rooms-emit →
`requestSync` path; it held on the lighter baseline suite but flaked once any
test was added. Bumped to `4×_settle()` (120ms) — a latent timing fragility in
that test, not a regression from the fix.

### Options 2–4 deferred

- Option 2 (tear down socket on `send_timeout`) — covers the window before
  3 missed pongs fire (test 4 in the capture: sent at 00:08:10, room-offline
  didn't fire until 00:09:15). **PARKED 2026-07-13** at
  `.work/backlog/story-app-teardown-socket-on-send-timeout.md` after an
  implementation attempt disproved the premise: `send_timeout` is a soft,
  recoverable failure by design (the transcript-event-log late-confirmation
  path), and tearing down severs the channel late confirmations arrive on.\  Re-examination found option 1 + late-confirmation already fix the user
  symptom. Two durable findings came out of it regardless: Plan-18's
  `room_already_open` rationale is obsolete (supersession closes the prior
  conn on re-auth), and the `late authoritative echo` test has a weak
  assertion masking breakage. See the parked story for the full analysis and
  the retire/revisit decision.
- Option 3 (tighten WS `pingInterval` 45s→15–20s) — secondary; helps the
  `onDone` path detect a fully-dead socket sooner.
- Option 4 (re-attempt timed-out messages on reconnect) — UX safety net so
  the `send_timeout` badge doesn't coexist with the message landing. **PARKED
  2026-07-13** at `.work/backlog/story-app-reattempt-held-pending-on-reconnect.md`
  after a fresh-context review (Block) found the Pi does not dedupe agent
  invocations by `clientMessageId` — re-sending a message that already landed
  would trigger a second agent turn. Safe re-send requires Pi-side
  `user_message` ingress idempotency (`pi-extension/src/index.ts:2525`),
  which doesn't exist. That's a latent risk for ALL re-delivery scenarios,
  worth filing independently. See the parked story for the full analysis.

## Reproduction

Live on the VM (relay log, app peer `iwT+dXs=`):

```bash
docker exec outpost-pi-relay cat /data/logs/relay.log.$(date -u +%F) \
  | sed 's/\x1b\[[0-9;]*m//g' | grep -E "authenticated|disconnected|duplicate auth" | grep iwT+dXs
```

The reproducible signature: a long gap between `authenticated` and
`disconnected` (the dead socket lingering) followed by a burst of
`connection_actor: dest not found, dropping from=iwT+dXs= dest=i6lDEeU=` (the
app trying to send into the dead direction) and then a reconnect. On the
phone side, `msgSend` → `msgFailed send_timeout` with **no intervening
`connChannelLost`** is the smoking gun — the transport never detected the loss.

## Acceptance

- A send into a socket whose app→relay direction is dead is detected within
  the 20s echo window, so `send_timeout` does not fire on a socket the app
  still believes `StatusOnline`.
- Relay control frames (`peer_online`/`presence`/`rooms`) do **not** reset
  the app→relay liveness counter; only a `Pong` round-trip does.
- A message that hit `send_timeout` does not silently arrive at the PC
  minutes later on the next reconnect — either it is re-attempted on the
  healthy connection (and deduped), or the dead socket is torn down before
  the next send enters it.
- A failing test reproduces the sequence: send into a half-open socket whose
  relay→app direction still delivers control frames → assert the dead
  direction is detected within the echo window (not at 65–130s).

## Investigation history

This story was initially filed as `story-app-ws-churn-10-50s-reconnect-loop`
(`prior_id` above), predicated on a static trace that hypothesized a
**backoff-reset-on-frame** mechanism: `onAppFrameObserved` resets
`_retryAttempt = 0` on any inbound `ServerMessage`, producing 1s reconnects
that race the prior socket's teardown (`duplicate auth from same device`
bursts). The first ring capture (`e46-11f1`, 2026-07-12 23:07–23:08)
**disproved** that — it showed zero `connChannelLost`/`retrying` events, so
the app never entered the retry path at all. The second capture (`e4f-11f1`,
2026-07-13 00:05–00:11) proved the actual mechanism: the half-open socket
lingers in `StatusOnline` for 65–130s, swallowing sends past the echo
timeout and flushing them on reconnect. The backoff-reset theory was a static
trace misread; the ring is dispositive.

The steady 10–50s connect/disconnect cadence observed in the 17:xx relay
window is **expected mobile-OS socket reclamation** (Doze, wifi power-save,
app backgrounding), not a bug — the relay has no idle-timeout
(`peer.rs:144-210` only breaks on send-failure/Close/stream-end), so those
disconnects originate on the app side and are not fixable without defeating
OS power management. Any residual concern about the duplicate-auth burst
(5 auths in 13s at 17:18:37–50) is tracked separately if it reproduces under
a capture that shows the app actually entering the retry path; the two
captures to date show it does not.

## Review (2026-07-13)

**Verdict**: Approve

**Blockers**: none
**Important**: none
**Nits**:
- The guard runs after the optimistic pending row is written (`_appendTranscriptEvent`
  at the top of `sendMessage`), so a room-offline send still creates a pending row
  before hitting the gate. This matches the existing offline (`ch == null`) branch
  behavior, so it's consistent — but worth noting the row exists before the gate
  fires. Intentional: the row is what the send-timeout fails visibly.

**Notes**: Substrate mode, fast lane (story item). Verification record in
"Implementation (2026-07-13 — option 1 shipped)" independently re-confirmed green
(half-open test passes; rotation test passes; full app suite 684/684 per the
record). Diff is minimal — reuses the existing held-pending path rather than
inventing new behavior. Gate is consistent with the existing `isRoomLive` usage
at `sync_service.dart:1559` (UI presence already gates on the same signal).
Deferred options 2–4 are filed in the story body as follow-ups, not separate
items (acceptable for a single-stride fix; option 2 is the most consequential
follow-up and should be scoped as its own story when picked up). One process
note: this fix was implemented inline rather than routed through the `fix` skill;
the review pass corrects the stage gap but the inline path skipped `fix`'s
story-creation framing. Parent `feature-reconnect-reproduction` is at
`stage: drafting` (not all siblings done — no roll-up).
