---
id: story-verify-mobile-dup-and-reorder-reconnect-repro
kind: story
stage: drafting
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
