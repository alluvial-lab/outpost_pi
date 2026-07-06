---
id: story-verify-mobile-dup-and-reorder-reconnect-repro
kind: story
stage: done
review_addressed: 2026-07-06
tags: [app, observability, bug, lifecycle, transcript]
parent: feature-reconnect-reproduction
depends_on:
  - feature-cross-side-observability
release_binding: null
gate_origin: null
created: 2026-07-06
updated: 2026-07-05
---

# Verify: mobile duplicate + reorder on reconnect (2026-07-06 ring-log repro)

## Brief

First live repro with the cross-side instrumentation shipped in
`feature-cross-side-observability`. Operator dropped wifi, reconnected, and
saw **a second copy of one message** on the phone plus **message reordering**.
The ring log (`debug/8e5-11f1-9243-4d82c1bdd26a.bin`, 227→127 KB across two
exports) captures the full reconnect state machine + the replay/dedup
sequence. This story attributes the duplicate + reorder to a specific surface
using that evidence, then decides whether it's the same root cause as
`story-mobile-assistant-message-duplicated-live-replay` (CONFIRMED, stage:
implementing) or a distinct surface.

## The repro (ring-log evidence, 2026-07-06)

### Timeline (3 reconnect cycles, all clean takeovers)
- `02:38:47` connChannelLost stale:false → retrying (1s→2s→5s backoff) → online `02:39:15` (28s)
- `02:42:18` connChannelLost stale:false → online `02:42:28` (10s)
- `02:44:42` connChannelLost stale:false → online `02:46:14` (92s)

All 3 `connChannelLost` are `stale:false` — the current channel died each time
(real loss → retry), NOT a duplicate-auth takeover. So the relay's
`superseded_existing` would be `false` (a fresh auth, not a duplicate) — this
isn't the half-open-TCP takeover case; it's a clean disconnect+reconnect.

### The duplicate signal
A `msgEcho` for `local_d974d2d7-94fc-4146-b460-dc0622639e53` at `02:41:51` —
a **foreign-device echo** (`local_` prefix, not the phone's `cli_` ids) with
NO corresponding `msgSend` from the phone. This is a message that originated
elsewhere (another device/session) being echoed to the phone. THIS is the
"second copy" the operator saw — it's a user message from elsewhere surfacing
as a visible duplicate.

### The reorder signal
**209 `wsIn` room-mismatch drops** — envelopes arriving with
`senderRoom: 7ADky8889NJy` (the operator's room id) but dropped because the
app's *active* room at arrival time didn't match. These drops are interleaved
with the reconnect cycles. Hypothesis: messages arrive, get dropped as
room-mismatch (active room transiently wrong during reconnect), then re-arrive
on the next reconnect's replay in a different order → the operator sees
reordering.

### Replay/dedup
300 `replayDedup` events (275 `dropped:true`, 25 `dropped:false`) across 9
replay bursts (one per reconnect). The 25 `dropped:false` are NEW events
accepted on replay — the question is whether one of those was already
rendered live (live×replay collision, the existing story's class).

## Distinct from `story-mobile-assistant-message-duplicated-live-replay`?

The existing story (CONFIRMED root cause, stage: implementing) is about
**assistant-message** duplication via live×replay eventId mismatch (random
uuid live vs deterministic replay). THIS repro shows:

1. A **user-message** echo (`local_` prefix) — a foreign-device user message,
   not an assistant message. Different message class.
2. **Room-mismatch drops** — a reordering surface the existing story doesn't
   address.
3. The duplicate is a **foreign echo**, not a live×replay collision of the
   phone's own message.

So this may be a **distinct surface**: (a) foreign-device user-message echo
rendering as a duplicate (the echo path may not dedup against an optimistic
row because there's no matching `cli_` id — the projection may insert it as a
confirmed foreign row, but if the phone already has it from a prior session,
it duplicates), and (b) room-mismatch drops causing reordering during the
active-room transient on reconnect.

OR it may share the existing story's identity root: if the live and replay
paths stamp incompatible eventIds for the foreign user message too, the same
class applies (just to user messages, not assistant messages).

## Scope (verify-then-decide, per the feature framing)

### Verify
- **The foreign-echo duplicate**: trace whether a `local_`-prefixed user
  message echo (no matching `cli_` optimistic row) gets inserted as a new
  confirmed row even if the phone already has that message from a prior
  session/replay. The echo dedup path (`sync_service.dart` `UserInput` case
  ~:634) dedupes against the optimistic row by `id` — but a foreign `local_`
  id won't match any `cli_` optimistic row, so it inserts as confirmed. If
  the phone already has it (from a prior replay with a different eventId),
  it duplicates. Confirm via the transcript store's eventId scheme for user
  messages: does the live echo path use a different eventId than the replay
  path for the SAME foreign user message? (The same class as the existing
  story, but for user messages — check `sync_service.dart` `UserInput` echo
  append + `session_history_replay.dart` `UserInputEvt`.)
- **The room-mismatch reorder**: trace why the active room is transiently
  wrong during reconnect (the envelopes have the right `senderRoom` but the
  app's `_activeRoomId` differs at arrival). Is `_activeRoomId` reset or
  stale during the reconnect window? Does the replay on reconnect re-establish
  it, but messages arriving before the replay completes get dropped? This is
  the reordering cause — dropped-then-re-arrived.
- **The ring-log correlation**: the 25 `replayDedup dropped:false` events —
  do any correlate (by eventIdTail) with the `local_` echo's message? If so,
  the foreign message was BOTH echoed live AND replayed → the duplicate.

### Decide
- If the foreign-echo duplicate is the SAME eventId-mismatch class as the
  existing story (just for user messages): fold into the existing story's fix
  (the deterministic-identity fix should cover user messages too, not just
  assistant messages).
- If it's a DISTINCT surface (foreign-echo dedup gap, or room-mismatch
  reorder): open a separate fix story with the verified root cause.
- If the room-mismatch reorder is a genuine separate bug (active-room
  transient on reconnect): open a fix story for the active-room
  re-establishment timing.

## Acceptance Criteria

- [ ] Static trace: does the `UserInput` echo path use a different eventId
      than the `UserInputEvt` replay path for the SAME foreign user message?
      (Cite file:line.) If yes → same class as the existing story.
- [ ] Static trace: why is `_activeRoomId` transiently wrong during reconnect
      (the 209 room-mismatch drops)? Cite the path.
- [ ] Cross-reference the 25 `replayDedup dropped:false` eventIds against the
      `local_` echo — do they collide?
- [ ] Decision: fold into `story-mobile-assistant-message-duplicated-live-replay`
      OR open a distinct fix story (with the verified root cause).
- [ ] No code change in THIS story (verify-then-decide).

## Out of scope

- The fix itself (separate story, post-attribution — either the existing
  story's deterministic-identity fix extended to user messages, or a distinct
  fix).
- The relay/extension (the relay delivered the frames correctly; this is
  app-side transcript/projection).

## References

- Parent: `feature-reconnect-reproduction.md`.
- Ring-log evidence: `debug/8e5-11f1-9243-4d82c1bdd26a.bin` (the reconnect
  export; 127 KB, 1001 events).
- Sibling (CONFIRMED, stage: implementing):
  `story-mobile-assistant-message-duplicated-live-replay.md` — the
  assistant-message live×replay eventId mismatch. This repro may extend it to
  user messages OR be a distinct surface.
- The code paths to trace:
  - `app/lib/data/sync/sync_service.dart` — `UserInput` echo case (~:634),
    the room-mismatch drop path (ws_in demux), `_activeRoomId` lifecycle.
  - `app/lib/data/sync/session_history_replay.dart` — `UserInputEvt` eventId.
  - `app/lib/data/transport/ws_transport.dart` — the `dropRoomMismatch`
    branch + `activeRoom` source.
  - `app/lib/data/transport/connection_manager.dart` — `_activeRoomId` reset
    on reconnect.
- The instrumentation that captured it (done): `feature-cross-side-observability`
  (`connChannelLost`, `connStatus`, `wsIn` room-mismatch, `replayDedup`,
  `msgEcho`).

## Static trace report

### Verdict

`TWO DISTINCT bugs (foreign-echo dup + room-mismatch reorder)`.

- The user-message live echo and replay paths do stamp incompatible transcript `eventId`s, so the identity defect is the same event-store class as `story-mobile-assistant-message-duplicated-live-replay`: live echo uses `server:user_confirmed:$id` while replay uses `server:$sessionId:user_input:$id:$ts` (`app/lib/data/sync/sync_service.dart:647-652`, `app/lib/data/sync/session_history_replay.dart:51-55`, `app/lib/data/sync/session_history_replay.dart:122-127`).
- The observed reorder/room-mismatch stream is a separate transport-room lifecycle defect: inbound demux drops any envelope whose `senderRoom` differs from the `WsTransport` room (`app/lib/data/transport/ws_transport.dart:107-110`, `app/lib/data/transport/ws_transport.dart:146-158`, `app/lib/data/transport/ws_transport.dart:371-375`).
- Nuance for the visible duplicate: unlike assistant rows, user-message projection keys the rendered row by `clientMessageId`, so two `UserMessageConfirmed` events for the same `local_...` id should collapse in the materialized transcript (`app/lib/domain/transcript/transcript_projection.dart:126-127`, `app/lib/domain/transcript/transcript_projection.dart:161-168`). The event-store identity mismatch is real, but the ring log does not prove that the specific `local_d974...` echo also replayed as one of the 25 accepted replay events.

### The foreign-echo duplicate attribution

Live `UserInput` echo path:

- `SyncService` handles `UserInput` by recording the echo, cancelling the pending-send timer for that id, and appending a `UserMessageConfirmed` (`app/lib/data/sync/sync_service.dart:635-647`).
- That live append uses `eventId: 'server:user_confirmed:$id'`, `ts: DateTime.now()`, and `clientMessageId: id` (`app/lib/data/sync/sync_service.dart:648-652`). This scheme is deterministic only over the echoed user id; it does not include the canonical session id or the server/history timestamp.

Replay `UserInputEvt` path:

- `sessionHistoryToTranscriptEvents` maps `UserInputEvt(id, text, image)` to `UserMessageConfirmed` with `clientMessageId: id` (`app/lib/data/sync/session_history_replay.dart:51-60`).
- The replay `eventId` is `serverReplayEventId(sessionId, 'user_input', id, event.ts)`, and `serverReplayEventId` formats that as `server:$sessionId:$historyType:$stableKey:$ts` (`app/lib/data/sync/session_history_replay.dart:52`, `app/lib/data/sync/session_history_replay.dart:122-127`).

Do they match? No. For the same foreign user message id `local_d974d2d7-94fc-4146-b460-dc0622639e53`, live would produce `server:user_confirmed:local_d974d2d7-94fc-4146-b460-dc0622639e53`, while replay would produce `server:<sessionId>:user_input:local_d974d2d7-94fc-4146-b460-dc0622639e53:<ts>` from the replay helper (`app/lib/data/sync/sync_service.dart:648-652`, `app/lib/data/sync/session_history_replay.dart:122-127`). That is the same event-store identity class as the confirmed assistant story, whose root cause is incompatible live/replay `eventId` schemes and Hive dedup by `eventId` (`.work/active/stories/story-mobile-assistant-message-duplicated-live-replay.md:45-52`, `.work/active/stories/story-mobile-assistant-message-duplicated-live-replay.md:87-103`, `app/lib/data/local/transcript_event_store_hive.dart:28-30`).

However, the rendered user row has an additional same-id guard that assistant rows lacked in the confirmed bug: projection dedupes authoritative messages by `ChatMessage.id` (`app/lib/domain/transcript/transcript_projection.dart:126-127`), and a `UserMessageConfirmed` projects to `UserMsg(id: event.clientMessageId, ...)` (`app/lib/domain/transcript/transcript_projection.dart:161-168`). Therefore a live+replay pair with the exact same `local_d974...` id would create two event-store entries but should not create two visible user bubbles unless another path gave the same logical text a different `clientMessageId`.

### The room-mismatch reorder attribution

The room-mismatch drops are transport-room state, not transcript identity:

- `WsTransport` demuxes every post-auth frame using `transport._activeRoom` (`app/lib/data/transport/ws_transport.dart:107-110`).
- If an envelope has a non-empty `room` but `senderRoom != activeRoom`, the demux returns `dropRoomMismatch` (`app/lib/data/transport/ws_transport.dart:361-375`), and the transport logs `stage: 'room-mismatch'` with the sender room (`app/lib/data/transport/ws_transport.dart:146-158`).
- A fresh `WsTransport` starts with `_activeRoom = 'main'`; only `setActiveRoom` changes it (`app/lib/data/transport/ws_transport.dart:275-287`).

Reconnect path:

- A channel loss schedules retry: `_watchChannel` listens for `onError`/`onDone`, `_onChannelLost` logs `stale:false`, cancels ping, marks transport closed, and calls `_scheduleRetry(peer)` (`app/lib/data/transport/connection_manager.dart:1192-1205`, `app/lib/data/transport/connection_manager.dart:1208-1236`). `_scheduleRetry` emits retrying and later calls `_connect(peer)` (`app/lib/data/transport/connection_manager.dart:1246-1260`).
- `_connect` sets `boundRoom = peer.roomId ?? 'main'` into `_activeRoomId` before connection, but the newly-created transport still has its own default `_activeRoom = 'main'` until the manager propagates it (`app/lib/data/transport/connection_manager.dart:520-545`, `app/lib/data/transport/ws_transport.dart:275-287`).
- After the factory returns, `_connect` calls `_propagateActiveRoom(_activeRoomId, ch)` before emitting `StatusOnline`, watching the channel/control streams, and replaying subscriptions (`app/lib/data/transport/connection_manager.dart:547-562`). `_propagateActiveRoom` is a dynamic best-effort call to `setActiveRoom`; if the channel does not support it, the default `'main'` remains (`app/lib/data/transport/connection_manager.dart:275-285`). Production wraps `WsTransport` in `PlainPeerChannel`, whose `setActiveRoom` forwards to the underlying transport (`app/lib/config/dependencies.dart:247-285`, `app/lib/data/transport/peer_channel.dart:57-67`).
- The adopt path is riskier: `adopt(IChannel channel, PeerRecord peer)` emits online, starts ping/watchers, and replays subscriptions without setting `_activeRoomId` from `peer.roomId` and without calling `_propagateActiveRoom` (`app/lib/data/transport/connection_manager.dart:425-451`). Pairing is the only direct caller of `adopt` (`app/lib/ui/pairing/viewmodels/pairing_viewmodel.dart:92-101`).

Ring-log correlation for the transient:

- The manager-side status was already logging room `7ADky8889NJy` at online/hydrate (`debug/8e5-11f1-9243-4d82c1bdd26a.bin:244-245`), but the immediately-following inbound envelopes with `senderRoom: "7ADky8889NJy"` were still dropped as `room-mismatch` (`debug/8e5-11f1-9243-4d82c1bdd26a.bin:251-252`). That combination means the stale/default room is the transport demux room (`WsTransport._activeRoom`), not necessarily `ConnectionManager._activeRoomId`, because the drop predicate compares the envelope room to the transport room (`app/lib/data/transport/ws_transport.dart:107-110`, `app/lib/data/transport/ws_transport.dart:371-375`).
- The same pattern recurs after the long reconnect: online/hydrate for room `7ADky8889NJy` is logged at `02:46:14` (`debug/8e5-11f1-9243-4d82c1bdd26a.bin:528-529`), followed by room-mismatch drops for `senderRoom: "7ADky8889NJy"` (`debug/8e5-11f1-9243-4d82c1bdd26a.bin:535-570`).

This is distinct from the duplicate identity bug: room-mismatch drops discard live envelopes before transcript handling, and later replay can append the missed events in replay order (`app/lib/data/transport/ws_transport.dart:146-158`, `app/lib/data/sync/sync_service.dart:1095-1133`).

### The replayDedup × local_ echo correlation

- The target foreign echo appears once in the ring log: `msgEcho id=local_d974d2d7-94fc-4146-b460-dc0622639e53` at line 343 (`debug/8e5-11f1-9243-4d82c1bdd26a.bin:343`).
- The local id's last 12 characters are `dc0622639e53`; its last 11 are `c0622639e53`.
- The 25 `replayDedup` entries with `dropped:false` are at lines 282-283, 388, 552-567, and 1016-1021, with tails `783305445058`, `783305445103`, `783305711430`, `783305711700`, `783305879133`, `783305879239`, `783305890702`, `783305890710`, `783305890710`, `783305895719`, `783305895726`, `783305902613`, `783305902619`, `783305902619`, `783305916943`, `783305916950`, `783305916950`, `783305939748`, `783305939757`, `783305987014`, `783305987023`, `783306021432`, `783306021440`, `783306021440`, and `783306036673` (`debug/8e5-11f1-9243-4d82c1bdd26a.bin:282-283`, `debug/8e5-11f1-9243-4d82c1bdd26a.bin:388`, `debug/8e5-11f1-9243-4d82c1bdd26a.bin:552-567`, `debug/8e5-11f1-9243-4d82c1bdd26a.bin:1016-1021`). None match `dc0622639e53` or `c0622639e53`.
- This absence is expected for replay ids because `serverReplayEventId` ends with `:$ts`, and the debug event stores only the last 12 characters of the event id (`app/lib/data/sync/session_history_replay.dart:122-127`, `app/lib/data/sync/sync_service.dart:1117-1122`). The ring log therefore does not show a direct `replayDedup` tail collision for the `local_d974...` echo.

### Recommendation

- Fold the user-message event-store identity mismatch into `story-mobile-assistant-message-duplicated-live-replay`: the deterministic-identity fix should also make live `UserInput` confirmation use the same canonical event id as `UserInputEvt` replay (`app/lib/data/sync/sync_service.dart:648-652`, `app/lib/data/sync/session_history_replay.dart:51-55`, `app/lib/data/sync/session_history_replay.dart:122-127`).
- Open a separate fix story for transport active-room re-establishment on reconnect/adopt. The fix should eliminate the window/default where `WsTransport._activeRoom` remains `'main'` or otherwise diverges from `ConnectionManager._activeRoomId`, and should cover the `adopt` path that currently does not propagate active room (`app/lib/data/transport/ws_transport.dart:275-287`, `app/lib/data/transport/connection_manager.dart:425-451`, `app/lib/data/transport/connection_manager.dart:547-562`).
- If the operator-visible duplicate persists after deterministic user-message identity is fixed, investigate a distinct user dedup surface where the same logical user text is stored under two different `clientMessageId`s, because same-id user confirmations should collapse during projection (`app/lib/domain/transcript/transcript_projection.dart:126-127`, `app/lib/domain/transcript/transcript_projection.dart:161-168`).
