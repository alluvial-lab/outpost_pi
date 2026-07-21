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

## Root cause: UNDETERMINED — do not commit to a theory

The cross-side evidence does not yet support a root cause. Below are the
raw facts and the specific gaps. A reproduction with both captures running
through the wake is needed before attributing.

### Raw facts (no interpretation)

**Extension delivery log:**
- `21:59:31.832` — `msg_received` for `cli_019f818a...` in room `SF_DCbXsmreE`
- *(nothing logged for ~2 hours)*
- `23:54:16.097` — `wake_outcome` ok=true for the same `cli_019f818a...`
- `23:54:16.098` — `msg_delivered` to session `67a5468b`

**Mobile ring log:**
- Ends at `21:59:53.674` (the `msgFailed` / send_timeout event)
- No events after 21:59:53 — the capture ended there

### What does NOT add up (open questions)

1. **What woke the message at 23:54?** The extension delivery log shows no
   `session_lifecycle`, no `message_api_armed`, no `command_ctx` at 23:54 —
   just the bare `wake_outcome` + `msg_delivered`. So whatever triggered the
   wake is not visible in the extension delivery log. The mobile capture had
   already ended, so it offers no 23:54 evidence either.

2. **Was the message genuinely "queued" on the extension side for 2 hours?**
   The operator reports they did NOT have a message queued — they set the
   session aside. If the app declared the message failed at 21:59:53, there
   should be no pending send. Yet the extension held `cli_019f818a...` as a
   pending wake from 21:59:31 until 23:54:16. The relationship between the
   app's send-timeout (21:59:53) and the extension's pending wake
   (21:59:31 → 23:54:16) is unclear.

3. **The earlier "operator idle + /new flushed it" theory is NOT supported
   by the logs.** There is no `/new` event at 23:54 on either side. That
   theory was speculative and should be disregarded.

### What IS confirmed

- The relay was clean throughout (no drops, no bad_envelope, no errors).
- The extension received the message at 21:59:31 (2s before the app even
  sent it per the mobile timestamp — a clock-skew or ordering note worth
  checking, but not a defect).
- The app declared the message failed at 21:59:53 (send_timeout, "no echo
  in 20s") despite the extension having received it.
- The mobile `msgEcho` at 21:59:33.733 carried id `sync_1784584771833`, not
  the `cli_...` id the app was waiting for, and `replayDedup` dropped it.
  This is a real app-side echo-misattribution symptom, but it is NOT yet
  confirmed as the root cause of the 2-hour wake gap.

## Disposition

Reproduced against post-0.2.0 code. Root cause UNDETERMINED. Do not commit
to a fix theory until a reproduction captures both traces through the wake.

The confirmed app-side symptom (echo misattribution → false send_timeout)
belongs to the `story-mobile-send-timeout-relay-room-main-mismatch` /
`story-mobile-double-messages-on-session-history-replay` symptom class.

The unexplained 2-hour wake gap needs a capture that includes the 23:54
trigger event (the mobile capture ended at 21:59:53, so whatever the
operator did at 23:54 was not captured on the mobile side).

Unbound from any release (not blocking 0.2.0, which has shipped). Route
through `feature-reconnect-reproduction`.
