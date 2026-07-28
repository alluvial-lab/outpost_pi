---
id: story-mobile-send-timeout-relay-room-main-mismatch
kind: story
stage: done
tags: [app, pi-extension, relay, bug, transport, lifecycle]
parent: feature-reconnect-reproduction
depends_on:
  - story-verify-mobile-dup-and-reorder-reconnect-repro
  - story-fix-transport-active-room-reestablishment-on-reconnect
release_binding: null
gate_origin: null
created: 2026-07-06
updated: 2026-07-07
reinvestigated: 2026-07-06
---

# Phone user message "not delivered" — relay sees `room=main` while app believes `7ADky...`

## Observed (2026-07-06 clean repro, ring log `949-11f1-9243-4d82c1bdd26a.bin`)

Operator sent a message from the phone at `14:42:47`:

```
3025 msgSend id=cli_019f37e1-... preview="second pass review yes, park the deferred item"
3024 workingConv room=7ADky8889NJy working:true   (mark_room_working)
3028 roomSnapshot room=7ADky8889NJy working:false  (22ms later — working flipped false)
3031 msgFailed id=cli_019f37e1-... code=send_timeout detail="no echo in 20s"
```

No `msgEcho` ever arrived for `cli_019f37e1...`. The phone showed "not
delivered" after the 20s timeout.

The workstation side concurrently logged:

```
[remote-pi] fanout-presence: Pi rejected message: agent session not bound yet
```

## Root cause (RE-INVESTIGATION 2026-07-06: relay evidence does NOT support the stated mechanism)

**The relay-drop evidence cited below was misread — the directionality is
backwards, and the relay shows zero phone-originated drops.** A live
re-inspection of the relay container (`remote-pi-relay`, up since 02:34 UTC)
found:

1. **Directionality.** `connection_actor.rs:126-167` (`dispatch_outer`)
   logs `from` = `self.peer_short` (authenticated **sender**) and `dest` =
   `env.peer` (destination), `room` = `env.room` (**destination** room). So
   the cited line `from=l2X/dUc= dest=MD/tL3E= room=main` is **Pi → phone**,
   not phone → Pi. `l2X/dUc=` is the Pi; `MD/tL3E=` is the phone.
2. **Zero phone-originated drops.** Across the full relay log there are
   **0** lines matching `from=MD/tL3E=` (phone as sender). Every drop is
   `from=l2X/dUc= dest=MD/tL3E= room=main` — the Pi pushing live events to
   the phone at the phone's OWN room `main` (the phone authenticates with
   `hello.room_id = 'main'`; `ws_transport.dart:250`). That `room=main` is
   CORRECT (it's the phone's room), and the drop fires only when the phone
   is offline (no live conn in `(MD/tL3E=, main)`). It is **not** a routing
   bug.
3. **No relay activity at the repro second.** The 14:42:47 UTC repro
   window (phone authed 14:40:17) has ZERO drop lines AND zero non-firehose
   relay lines. If the phone's envelope had reached the relay and been
   dropped for a room mismatch, there would be a `from=MD/tL3E=` drop at
   ~14:42:47. There is none. So the phone's send either (a) never reached
   the relay (app-side transport never flushed), or (b) reached the relay
   and was forwarded successfully (no drop) but the Pi did not echo — a
   Pi/extension-side issue, NOT a relay room-routing drop.

### What this means for the fix

- The reorder fix (`80b04e5`) is still defensible on its own merits
  (`_activeRoom` defaulting to `'main'` is a real latent bug for the
  inbound demux and for correctly targeting the Pi's cwd-room), but it is
  **not** the confirmed cause of this send_timeout — the relay logs do not
  show the phone→Pi `room=main` drops the story claimed.
- The "agent session not bound yet" extension symptom remains a separate
  recoverable condition (see below).
- **Re-opened question**: what actually consumed the phone's 14:42:47 send
  for 20s with no echo? Candidates: (a) app-side transport stuck/not
  flushing (the `msgSend` fired but the WS frame never went out); (b) relay
  forwarded it and the Pi/extension received it but didn't echo (session
  not bound, or wrong room targeted silently). Needs the extension's own
  debug log for the 14:42:47 instant, or a decoded ring-log WS-send event,
  to distinguish.

### This is the SEND-side twin of the reorder bug

`story-fix-transport-active-room-reestablishment-on-reconnect` fixed the
INBOUND demux race (transport `_activeRoom` defaulting to `'main'` dropped
inbound envelopes as `room-mismatch`). The SEND path has the SAME root:
`WsTransport.send` stamps the outer envelope's `room` field from
`_activeRoom` (`app/lib/data/transport/ws_transport.dart:303-310`), so a
transport stuck at `'main'` sends envelopes the relay can't route.

### Why the fix didn't help this repro

The reorder fix (`80b04e5`) constructs `WsTransport` with
`peer.roomId ?? 'main'` at `connect()` time. BUT:

1. **The fix is not deployed.** These are source commits; the phone is
   running an older APK. The ring log (`14:42`) predates any rebuild +
   sideload. The relay's `room=main` on outbound envelopes is the pre-fix
   behavior.
2. **Even with the fix, the `peer.roomId` may be `null` or stale.** If the
   `PeerRecord.roomId` is null (legacy peer, pre-Plan-17) or the room
   changed since the last pairing, `peer.roomId ?? 'main'` falls back to
   `'main'` and the discovery flow (`_maybeAdoptLegacyRoom`) is relied on
   to patch it. If a send happens before discovery patches, it goes to
   `main`.

### The "agent session not bound yet" is a SEPARATE symptom

The workstation's `[remote-pi] fanout-presence: Pi rejected message: agent
session not bound yet` is the extension's `_sendPiMessage` returning false
because `messageApi` is null (`pi-extension/src/session/sdk_session_projection.ts:522-524`,
`pi-extension/src/index.ts:620-627`). This fires when the extension tries
to inject the `remote-pi:fanout-presence` customType INTO the Pi runtime
(`sendMessage`) but the session isn't bound (startup race / replacement
window). It is NOT the user message being rejected — the user message
never reached the Pi because the relay dropped it at `room=main`.

Two failure layers stacked: the relay dropped the user message (room
mismatch), AND the extension's fanout-presence notification couldn't be
injected (session not bound). The operator sees both.

## The fix (REVISED — pending re-confirmation of the actual failure path)

1. **Do NOT assume the reorder fix resolves this send_timeout.** The relay
   logs do not show the phone→Pi `room=main` drops the original story
   claimed. Deploying `80b04e5` is still worthwhile (latent inbound-demux
   fix) but must not be credited with fixing this bug without a live repro
   confirming the symptom is gone.
2. **Re-confirm the failure path** before fixing: capture the extension's
   debug log AND a decoded ring-log WS-send event at a fresh repro instant.
   Distinguish: (a) phone never sent the WS frame (app transport stuck) vs
   (b) relay forwarded and Pi didn't echo (extension session/echo bug).
3. **The fanout-presence "session not bound"** remains a separate
   recoverable condition worth silencing/queuing, but it is NOT the user
   message being rejected (the user message's actual fate is the open
   question in #2). See `story-extension-suspend-fanout-on-peer-offline`.

## Acceptance Criteria (REVISED)

- [x] **RELAY EVIDENCE RE-CHECKED (2026-07-06)**: the cited
      `from=l2X/dUc= dest=MD/tL3E= room=main` drop is Pi→phone (correct
      room=phone's `main`), NOT phone→Pi. Zero `from=MD/tL3E=` drops in
      the full relay log. Zero relay activity at the 14:42:47 repro second.
      The stated relay-room-main-drop mechanism is **unsupported**.
- [x] **DOMINANT ROOT CAUSE CONFIRMED (2026-07-07)**: the 77% inbound
      demux drop rate (ring log `9c1-...bin`, 05:00–05:06 UTC, already
      cited in `story-fix-transport-active-room-reestablishment-on-reconnect`)
      proves `WsTransport._activeRoom` was stuck at `'main'` in production.
      `send()` stamps `room: _activeRoom` (`ws_transport.dart:312`) — the
      SAME field the inbound demux compares against (`ws_transport.dart:388`).
      So the outbound send was routing to `'main'` too. The fix `80b04e5`
      (construct `WsTransport` with the correct room from frame 1) covers
      BOTH directions. The "zero phone-originated relay drops" for the
      14:42 repro is consistent with that specific instance being
      half-open TCP (phone wrote to a dead socket the relay never saw —
      tracked in `idea-mobile-drop-half-open-tcp`), but the `room=main`
      bug is the dominant, confirmed, high-frequency cause the fix
      addresses. If `send_timeout` persists after deploy, investigate
      half-open TCP next.
- [x] **FIX IN SOURCE** (`80b04e5`, `stage: review`): constructs
      `WsTransport` with `activeRoom: peer.roomId ?? 'main'` at connect
      (`dependencies.dart:276,321`), eliminating the default-`'main'`
      race for both send and inbound demux.
- [ ] **DEPLOY + VERIFY**: rebuild + sideload the app APK; confirm a
      fresh ring log shows zero `room-mismatch` drops AND no
      `send_timeout` on a normal send.
- [x] Separately: silence/queue the fanout-presence "session not bound"
      recoverable error — DONE in `story-extension-suspend-fanout-on-peer-offline`.

## Out of scope

- The dup/reorder identity fixes (separate stories, landed).
- The relay's `dest not found` logging (it's correct — there's no Pi in
  `room=main`).

## References

- Ring log: `debug/949-11f1-9243-4d82c1bdd26a.bin:3023-3031` (the failed
  send + 20s timeout).
- Relay logs: `room=main` on the phone's outbound, `dest not found` drops.
- `app/lib/data/transport/ws_transport.dart:250` — `hello.room_id = 'main'`
  (the app's OWN room, correct).
- `app/lib/data/transport/ws_transport.dart:303-310` — `send` stamps
  `room: _activeRoom` (the DESTINATION room — this is the stuck-`'main'`
  field).
- `story-fix-transport-active-room-reestablishment-on-reconnect` (done,
  stage: review) — the inbound twin of this bug.
- `.work/backlog/idea-mobile-user-message-not-delivered-timeout.md` — the
  original idea (now grounded with a confirmed root cause).

## Retirement (2026-07-28)

Closed/archived with parent epic `epic-targeting-and-session-lifecycle-contracts`.
The observability unlock shipped; this bug was either resolved by it,
re-investigated with its original mechanism disproven, or left unreproduced
with instrumentation in place and no recurrence in 3+ weeks. See the epic's
retirement note for the full disposition.
