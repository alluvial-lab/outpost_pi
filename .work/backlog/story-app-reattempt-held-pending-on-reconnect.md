---
id: story-app-reattempt-held-pending-on-reconnect
created: 2026-07-13
updated: 2026-07-13
tags: [app, bug, lifecycle, transport]
status: parked
follow_up_of: story-app-half-open-socket-swallows-sends-arrives-late
---

# ⏸ PARKED — Re-attempt held-pending messages on reconnect (half-open option 4)

> ## STATUS: PARKED — blocked on Pi-side agent-invocation idempotency
>
> **Not safe to ship as implemented.** A fresh-context review (`gpt-5.6-sol`)
> found two blockers. The fix was reverted; the analysis is preserved below.
>
> **TL;DR.** Option 4 (re-send held-pending messages on reconnect) is the one
> half-open option that is NOT redundant with existing mechanisms — a held-pending
> message was never sent, so late-confirmation can't recover it. But the
> implementation uncovered that **the Pi does not dedupe agent invocations by
> `clientMessageId`.** Re-sending a message that already reached the Pi (race
> window) would trigger a **second agent turn** — the transcript/UI dedupes by
> id, but `_wakeAgent` runs before the dedupe. And the `_onRoomsChanged` hook is
> too broad: the re-send's own `working:true` emission re-fires it, and since
> `held` isn't cleared, it self-retriggers.
>
> **The blocker is on the Pi side, not the app side.** Safe re-send requires
> the extension to dedupe incoming `user_message` frames by `(session_id,
> msg.id)` BEFORE `_wakeAgent` — i.e. an ingress idempotency guard in
> `pi-extension/src/index.ts` (`_attemptUserDelivery` / the `user_message`
> handler at ~line 2525). Without that, ANY re-send is unsafe.
>
> **Two paths forward (operator decision, deferred):**
>
> 1. **Park until Pi-side idempotency exists.** File a separate story for
>    extension-side `user_message` ingress dedupe by `(session_id, msg.id)`.
>    Once that lands, this story's re-send becomes safe (the race-window
>    duplicate is dropped at the Pi ingress, not double-executed). *(Recommended
>    sequence.)*
> 2. **Drop.** If the held-pending failure is rare enough in practice (the room
>    must be offline for >20s AND the user must send during that window), the
>    permanent-failure badge may be acceptable. Option 1 + late-confirmation
>    already handle the common case (message landed).
>
> **Durable finding (carries forward regardless):** the extension's
> `user_message` ingress (`pi-extension/src/index.ts:2525`) has NO idempotency
> guard by `msg.id` — `_attemptUserDelivery` calls `_wakeAgent` before
> `_confirmUserDelivery` records the confirmation. This is a latent risk for
> ANY re-delivery scenario (reconnect flush, relay fan-out, cross-PC mesh),
> not just this story. Worth filing independently.

---

## Brief (original premise — still valid, but blocked on Pi-side idempotency)

Direct follow-up to `story-app-half-open-socket-swallows-sends-arrives-late`
(option 1, shipped `6d64556`). Option 1 gates `sendMessage` on room liveness:
when the room is offline, the message is held pending (optimistic row + armed
timeout, NOT written to the channel). The option-1 comment said this "re-attempts
on the next healthy connection" — but the re-attempt was never implemented.
The held-pending message fails at `send_timeout` and stays failed permanently.

This is the ONE half-open option NOT redundant with existing mechanisms.
Options 2 and 3 were parked after investigation found option 1 + late-confirmation
already fix the symptom for messages that *landed*. But late-confirmation only
works if the message reached the Pi — a held-pending message was never sent,
so `SessionHistory` can't confirm it.

## The attempted fix (reverted — not safe)

1. Added a `held: bool` field (default false) to `UserMessageSubmitted`,
   set true when the send was held pending. (This part is sound — backward-
   compat verified.)
2. `_resendHeldPendingMessages`: on room-snapshot change, re-send held
   pending/failed messages with the original `clientMessageId` so the
   echo/replay dedupes by id.

## Review findings (2026-07-13, `gpt-5.6-sol`, Verdict: Block)

### Blockers

1. **Stable message ID does not make agent delivery idempotent.** Reusing
   `clientMessageId` dedupes the *transcript/UI* (`transcript_projection.dart`
   confirmedUsers/failedUsers keyed by id; `session_history_replay.dart:51`
   preserves the original id). But the Pi's `_attemptUserDelivery`
   (`pi-extension/src/index.ts:2287`) calls `_wakeAgent` BEFORE
   `_confirmUserDelivery` records the confirmation, and the `user_message`
   ingress (`index.ts:2525`) has NO dedupe by `msg.id`. A duplicate frame
   triggers a second agent turn. Transcript dedupe happens after and cannot
   undo that work.

2. **The retry hook can re-send in response to the delivery it just
   initiated.** `_onRoomsChanged` fires on ANY room-snapshot change — including
   the `working:true` room_meta update the Pi publishes after accepting the
   re-sent message. Since `held` is not cleared, that update can re-send the
   prompt before its echo is committed → self-retrigger loop.

3. **Reconnect can re-send before fresh room authority exists.**
   `_liveRoomIds` is not cleared on disconnect; on reconnect, `roomsStream`
   emits before fresh control snapshots arrive, so `isRoomLive` can expose
   stale liveness and trigger the retry prematurely.

### Important

- **Resend drops steering semantics.** `UserMessageSubmitted` doesn't persist
  `streamingBehavior`; a held steer becomes a normal prompt.
- **No post-await lifecycle validation.** After `readSession`, the method
  doesn't verify `_activeRef == ref` or `_conn.channel == ch` — a same-peer
  room switch during the async read could misdeliver.
- **Multiple held prompts have undefined delivery semantics** — all written
  sequentially without ack/queue semantics.
- **The test proves only one outbound write** — it doesn't produce an echo,
  `working` update, or Pi-side delivery, so it can't detect the double-execution
  bug.

### Nits

- `_resendHeldPendingMessages` builds `failedIds` but never reads it.
- Its doc says it "Clears `held`" but the implementation doesn't.

## The prerequisite: Pi-side ingress idempotency

The root blocker is that the extension does not dedupe incoming `user_message`
frames by `(session_id, msg.id)`. The `user_message` handler at
`pi-extension/src/index.ts:2525` calls `_deliverUserMessage` →
`_attemptUserDelivery` → `_wakeAgent` unconditionally. A guard that checks
whether `msg.id` was already delivered in the current session — and if so,
re-echoes (idempotent confirmation) but does NOT re-invoke the agent — would
make ANY re-delivery safe (reconnect flush, relay fan-out, cross-PC mesh,
AND this story's re-send). This is the prerequisite that unblocks option 4.
It should be filed as its own story — it's independently valuable (latent
risk for all re-delivery scenarios), not just a dependency for option 4.

## References

- `app/lib/data/sync/sync_service.dart:245-360` — `sendMessage` (held-pending guard).
- `app/lib/data/sync/sync_service.dart:634` — `_resendHeldPendingMessages` (the reverted method).
- `app/lib/data/sync/sync_service.dart:693-716` — `_onRoomsChanged` (too-broad hook).
- `app/lib/domain/transcript/transcript_event.dart:19-40` — `held` field (sound; backward-compat verified).
- `app/lib/data/local/records/transcript_event_record.dart:79-90,145-160` — serialization (sound).
- `app/lib/domain/transcript/transcript_projection.dart:117-175,250-263` — UI dedupe by clientMessageId (sound, but not execution dedupe).
- `pi-extension/src/index.ts:2287` — `_attemptUserDelivery` → `_wakeAgent` before `_confirmUserDelivery` (THE BLOCKER).
- `pi-extension/src/index.ts:2525` — `user_message` ingress, no idempotency guard (THE BLOCKER).
- `app/lib/data/sync/session_history_replay.dart:51` — `UserInputEvt` → `UserMessageConfirmed` (late-confirmation; only works if the Pi has the msg).
- `.work/backlog/story-app-teardown-socket-on-send-timeout.md` — option 2 (parked); documents why options 2/3 are redundant.
- `story-app-half-open-socket-swallows-sends-arrives-late.md` — option 1 (shipped); options 2–4 filed in its body.
