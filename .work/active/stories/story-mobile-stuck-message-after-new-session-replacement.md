---
id: story-mobile-stuck-message-after-new-session-replacement
kind: story
stage: drafting
tags: [app, pi-extension, relay, bug, transport, session, lifecycle]
parent: feature-reconnect-reproduction
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-21
updated: 2026-07-20
reproduced: 2026-07-20
---

# Mobile message stuck after `/new` session replacement — echo misattribution + 2h wake delay

## Symptom

Operator initiated `/new` from the mobile app (session replacement), then sent
a message. The message appeared stuck ("failed and got stuck") on the mobile
side. The message was actually received by the extension but did not wake the
agent session for ~2 hours.

## Reproduction (2026-07-20, post-0.2.0 code)

Trigger: `/new` from mobile (session replacement in room `SF_DCbXsmreE`),
then send a message ~30s later.

Cross-side traces:
- Mobile ring log: `debug/486-11f1-ae25-659bdda1075d.bin`
- Extension delivery log: `~/.pi/remote/debug/delivery.log`
- Relay log: `outpost-pi-relay` container, `RUST_LOG=info,relay=debug`

Message id: `cli_019f818a-9f94-7b30-9c62-5fa81350b84c`
Session: `67a5468b` (new session after `/new`), room `SF_DCbXsmreE`

## Evidence — cross-side timeline

### Mobile side (`486-11f1-ae25-659bdda1075d.bin`)

```
21:59:02  /new initiated (session replacement)
21:59:03.804  room_meta_updated (room_ended for old)
21:59:04.946  room_announced (new session room SF_DCbXsmreE)
21:59:33.528  workingConv room=SF_DCbXsmreE working:true (mark_room_working)
21:59:33.542  msgSend id=cli_019f818a... blocked:false   ← message sent
21:59:33.733  msgEcho id=sync_1784584771833              ← echo, but WRONG id
21:59:33.762  replayDedup sessionId=019f818a... dropped:true  ← dedup DROPPED something
21:59:53.564  msgFailed id=cli_019f818a... code=send_timeout "no echo in 20s"  ← declared failed
```

### Extension side (`delivery.log`)

```
21:59:02.031  session_lifecycle reason=new roomId=SF_DCbXsmreE sessionIdTail=""  (old session tearing down)
21:59:02.031  message_api_null reason=shutdown
21:59:03.025  message_api_armed via=factory sessionIdTail=019f80bc... roomId=SF_DCbXsmreE  (new session)
21:59:03.026  session_lifecycle reason=new sessionIdTail=67a5468b roomId=SF_DCbXsmreE
21:59:03.061  message_api_armed via=withSession sessionIdTail=67a5468b roomId=SF_DCbXsmreE  (re-armed)
21:59:31.832  msg_received id=cli_019f818a... source=app roomId=SF_DCbXsmreE  ← extension GOT the message
              <gap — no wake_outcome, no msg_delivered for ~2 hours>
23:54:16.097  wake_outcome id=cli_019f818a... ok:true messageApiArmed:true roomId=SF_DCbXsmreE
23:54:16.098  msg_delivered id=cli_019f818a... sessionIdTail=67a5468b roomId=SF_DCbXsmreE
```

### Relay side

No `outbound_queue_dropped`, no `bad_envelope`, no errors. The relay forwarded
cleanly — the failure is on the app↔extension delivery path, not the relay.

## Root cause analysis

### The 2-hour gap is operator idle time, not a wake hang

The mobile ring log ends at 21:59:53 (the `msgFailed` event). The extension
delivery log shows **nothing** for room `SF_DCbXsmreE` between 21:59:53 and
23:54:16 — no session lifecycle, no message_api changes, no events. The
operator set the session aside for ~2 hours and picked it back up with a
`/new` from the phone at ~23:54, which re-armed the session and flushed the
queued message through (`wake_outcome` + `msg_delivered` at 23:54:16).

So the 2-hour gap is NOT a wake-path hang. The real defect is entirely
mobile-side.

### The defect: echo misattribution → false `send_timeout` (app side)

The mobile app sent `cli_019f818a...` at 21:59:33.542. 190ms later it
received a `msgEcho` — but with id `sync_1784584771833`, NOT the `cli_...`
id it was waiting for. The `replayDedup` event at 21:59:33.762 dropped
something (`dropped:true`), suggesting the echo was misattributed to a
replay/session-sync frame rather than the live send. Because the app never
saw an echo for `cli_019f818a...`, the 20s send-timeout fired at 21:59:53
and declared the message **failed** — even though the extension had already
received it (21:59:31, 2s BEFORE the send) and the message was in-flight.

The message then sat queued on the extension side until the operator's
later `/new` flushed it ~2h later. The mobile showed the message as
failed/stuck the entire time.

This matches the existing `story-mobile-send-timeout-relay-room-main-mismatch`
symptom class: the app declares `send_timeout` when the real issue is an
echo/replay attribution problem, not a relay delivery failure.

## Attribution

- **App side:** the echo misattribution + false `send_timeout` is the app's
  send-ack path conflating a replay/session-sync echo (`sync_` id) with the
  live send echo (`cli_` id). The app declares the message failed while the
  extension has already received it.
- **Extension side:** no defect — the message was received and queued
  correctly; the ~2h delay before delivery was operator idle time followed
  by a `/new` that flushed it.
- **Relay side:** no defect — forwarded cleanly, no drops.

## Disposition

Reproduced against post-0.2.0 code. The 0.2.0 lifecycle/buffer work did NOT
fix the echo-misattribution defect. It is the same symptom class as
`story-mobile-send-timeout-relay-room-main-mismatch` and
`story-mobile-double-messages-on-session-history-replay`.

The fix is app-side: the send-timeout path must not fire when the extension
has confirmed receipt (`msg_received`), and the echo attribution must not
satisfy a `cli_` send-ack wait with a `sync_` id from a replay/session-sync
frame.

Unbound from any release (not blocking 0.2.0, which has shipped). Route
through `feature-reconnect-reproduction`.
