---
id: story-mobile-cross-session-history-leak
kind: story
stage: drafting
tags: [app, pi-extension, relay, bug, transport, session]
parent: feature-reconnect-reproduction
depends_on:
  - story-verify-mobile-dup-and-reorder-reconnect-repro
release_binding: null
gate_origin: null
created: 2026-07-06
updated: 2026-07-06
reinvestigated: 2026-07-06
---

# Mobile chat receives `session_history` from non-active Pi sessions (cross-room leak)

## Observed (2026-07-06, ring log `949-11f1-9243-4d82c1bdd26a.bin`)

Operator reports that **skills/ and starmods/ sessions appear as messages in
the mobile chat** — i.e. the phone is rendering transcript content from Pi
sessions that are NOT the active chat session. The ring log confirms: in the
`14:40–14:43` window (active room `7ADky8889NJy`, active session
`...f05f3343`), **3 distinct sessions** replayed through the app's
`_replayHistory` path:

```
replayDedup sessionIds (last 8) in 14:40-14:43 window:
  c12db9c7: 30 events   (14:40:21)
  06c8acbf: 30 events   (spans 07:17 → 14:41)
  f05f3343: 30 events   (the active session)

### Operator clarification (2026-07-06) — the symptom is subagent traffic, not cross-room session content

The operator clarified the report is NOT (primarily) about sibling cwd-room
sessions leaking in. It is: **when a session's main agent dispatches a
subagent (in skills/ and starmods/), the subagent's messages and its
report back to the main agent showed up in the mobile chat.** This is a
transcript-message delivery issue, not a `room_meta` session-flip.

### Mechanism finding (2026-07-06 static trace)

The SDK fires `message_end` for subagent assistant turns *within the parent
session* — subagent dispatch is NOT a `session_start` reason (SDK reasons are
only `startup | reload | new | resume | fork`; `extensions.md:395`). The
extension's `message_end` handler (`sdk_session_projection.ts:387-425`)
broadcasts every assistant text block as `agent_message` stamped with
`sessionId = this.currentRemoteSessionId()` (the parent/main session id),
gating only on `message.role === "assistant"` and `block.type === "text"` —
no source/subagent discrimination. So the subagent's report-back is an
assistant message in the main session, projected as `agent_message` and
fanout-broadcast to the phone, appearing in chat alongside the main agent's
own messages.

This is a **correct-session, wrong-content** leak: the session id is right
(the parent), but the content is subagent-internal traffic the operator does
not want surfaced in the mobile chat. The relay `cross_room` logging deployed
in `story-relay-log-room-meta-update-accept-and-drop` does NOT catch this —
it targets the wrong layer (room-meta routing, not transcript broadcast).

### Two distinct failure modes now in scope

1. **Subagent-content leak (the operator's actual report)** — extension
   `message_end` broadcasts subagent assistant text to the phone. Needs an
   extension-side gate (suppress broadcast for subagent-origin assistant
   messages, or the SDK needs a source/subagent field the projection can
   filter on). Whether the SDK message carries any subagent/source metadata
   is UNVERIFIED — the `extensions.md` message shape does not document one,
   but the runtime `event.message` may carry a field worth checking.
2. **Cross-room session flip (the original h1/h2 ambiguity, lower priority)**
   — the `_activeRef` rotation captured in the ring log. May be unrelated to
   the operator's report; may be a real but separate bug. Keep the refined
   open question (does the extension send `room_meta_update` for a sibling
   room?) but treat it as secondary to #1.
```

`replayDedup` only fires inside `_replayHistory` (`sync_service.dart:1199`),
which only runs AFTER the session gate accepts the `SessionHistory` frame
(`sync_service.dart:569`, `sync_service.dart:844-846`). So the gate ACCEPTED
`session_history` frames for 3 different sessions — meaning `_activeRef.sessionId`
matched all 3 at some point, OR the gate is being bypassed.

Across the full ring log, **7 distinct sessions** replayed (390+300+90+60+60+
30+30 events). The phone sees a firehose of cross-session transcript content.

## Root cause (PARTIALLY CONFIRMED 2026-07-06 — deeper trace needed before fixing)

**Confirmed:** the active session (`_activeRef.sessionId`) changed 5 times in
3 minutes while `_activeRoomId` stayed `7ADky8889NJy`. The session gate is
correct; `_activeRef` is being mutated by room-metadata events.

**NOT confirmed:** the EXACT mutation path. A focused static trace found that
NONE of the 3 room handlers (`RoomAnnounced`/`RoomMetaUpdated`/`RoomsSnapshot`)
can mutate room `7ADky`'s `sessionId` from a sibling room's announcement —
they all key by `roomId` and only touch the announced room's entry. The relay
keys rooms by `(peer_epk, room_id)` and does not mis-route
`room_meta_updated` across rooms. So a sibling Pi's metadata for
`SF_DCbXsmreE` cannot flip `7ADky`'s `sessionId`.

### NEW structural fact (2026-07-06 live relay inspection)

All 4 dev-VM Pi processes authenticate under the **SAME owner epk** `l2X/dUc=`
— rooms `SF_DCbXsmreE` (02:35), `7ADky8889NJy` (02:36/03:19/17:53),
`zuMPC-YTtdUD` (07:03), `k0H-7lFh371e` (07:04/17:10). They share one owner
keyring (the dev VM's `~/.pi/agent`). The phone (`MD/tL3E=`) is in
`room=main` only. Two relay-structural consequences the prior traces missed:

1. **`room_meta_update` keys by `(peer_id, room_id)` and drops unknown pairs**
   (`control.rs:143-167`, `rooms.rs:apply_patch`). A sibling Pi sending
   `room_meta_update` for room `7ADky` resolves to key `(l2X/dUc=, 7ADky)` —
   which EXISTS (the 7ADky Pi registered it). So a sibling could stamp a new
   session_id onto the `7ADky` room entry via the shared peer_id. This is a
   **candidate leak path the prior static trace missed**: does the extension
   ever send `room_meta_update` for a room it did NOT register (a sibling
   room id)? The relay would accept it under the shared peer_id.
2. **`RoomManager.subscribe` is keyed by peer_id, not room** (`rooms.rs:56`).
   `subscribers_of("l2X/dUc=")` returns the phone for ALL of that peer's
   rooms. So the phone RECEIVES `room_meta_updated` frames for all 4 sibling
   rooms under the one shared peer_id. The app's `RoomMetaUpdated` handler
   must not auto-activate to a sibling's session from these. This is the
   delivery-side precondition for the h2 leak.

### The 7ADky Pi did NOT re-auth during the repro window

The `7ADky` Pi's connections authenticated at 02:36:31 and 03:19:38, then
NOT AGAIN until 17:53:34 — so no reconnect rotation during 14:40-14:43.
Any session rotation in that window came via `room_meta_update` frames, not
re-auth. The relay doesn't log `room_meta_update` at INFO, so relay logs
alone cannot confirm whether `7ADky`'s session_id was rotated by the 7ADky
Pi's own process (h1, correct) or overwritten by a sibling via the
shared-peer_id path (h2-leak-variant).

**Two remaining hypotheses:**

1. **The `7ADky` Pi's OWN session rotated multiple times** (via `/new`/
   `/resume` during the operator's autopilot/review work). Each rotation
   publishes `room_meta_updated` with a new `session_id` for room `7ADky`.
   The app correctly tracks it (`RoomMetaUpdated` → `RoomInfo.sessionId` →
   `_onRoomsChanged` → `activate()`). The replayed sessions (`c12db9c7`,
   `06c8acbf`, `96bc2b30`) are PRIOR sessions of the SAME `7ADky` Pi. This
   is CORRECT behavior — the app hydrates each rotated session's history on
   reconnect. The operator may have mistaken the agent's own skills/starmods
   discussion content for sibling-Pi content.
2. **Cross-room leak via the phone being in `room=main`.** The sibling Pis
   (in `SF_DCbXsmreE`/`zuMPC`/`k0H-7l`) broadcast to the phone at
   `room=main` (the phone's registered room) — `OwnerMultiplexer.broadcast`
   has no room filter, and the relay delivers `(phone_epk, main)` to the
   phone. The sibling's `session_history` carries the sibling's `session_id`.
   For the gate to accept it, `_activeRef.sessionId` must have flipped to the
   sibling's — but the static trace shows no path for that. UNLESS the
   sibling's `session_history` is being accepted via a DIFFERENT gate path,
   or `_activeRef` is null (the `active_session_unknown` gate rejection at
   14:40:17.636 suggests `_activeRef` was briefly null right after reconnect).

### What the evidence supports

- The relay shows only ONE Pi process in room `7ADky` (2 auths, both from
  the dev VM). The 4 Pis are in 4 different rooms.
- The current pi session (`019f3570-42c7-...`) does NOT appear in the
  replayDedup sessionIds — so the replays are NOT the current session's
  history. They are prior/sibling sessions.
- Hypothesis (1) is consistent with the operator running autopilot/reviews
  (which rotate sessions via `/new`). Hypothesis (2) is consistent with the
  operator's report of sibling-Pi content appearing.

### Why this is parked, not fixed

The root cause is genuinely ambiguous between (1) correct session-rotation
tracking and (2) a cross-room leak. Implementing a fix on the wrong
hypothesis risks breaking correct reconnect-hydration behavior (1) or
missing the actual leak (2). The ring log does not decode `room_meta_updated`
payloads or `session_history` wire `session_id` fields, so it can't
distinguish them.

**Needed before fixing:**
- A live repro with the ring log decoding `room_meta_updated` room +
  session_id, AND the `session_history` wire `session_id` — so we can see
  whether the flipped sessions are the `7ADky` Pi's own rotations or sibling
  Pis' sessions.
- OR: a check whether the operator was running autopilot/`/new` on the
  `7ADky` Pi during the 14:40-14:43 window (which would confirm hypothesis 1).

## The fix (TBD — depends on confirmed hypothesis)

- If (1): no fix needed — the app is correctly tracking session rotations.
  The operator's report may be a misread.
- If (2): app-side — `_onRoomsChanged` must not `activate()` to a sibling
  session; extension-side — `OwnerMultiplexer.broadcast` must filter by
  room (requires per-owner room tracking).

## Acceptance Criteria

- [x] Static trace: does `_activeRef` change when a `RoomAnnounced` for a
      SIBLING room arrives while a different chat is open? **NO direct path**
      — the 3 room handlers key by `roomId` and can't mutate a sibling room's
      `sessionId`.
- [x] Static trace: does the extension broadcast `session_history` to ALL
      attached owners, or only those in the Pi's cwd-room? **ALL** —
      `OwnerMultiplexer.broadcast` (`owner_multiplexer.ts:450-454`) has no
      room filter.
- [x] Confirm via the ring log: the active session changed 5 times in 3 min
      while the room stayed `7ADky`.
- [x] **RELAY (2026-07-06 live)**: all 4 dev-VM Pis share one owner epk
      `l2X/dUc=`; `room_meta_update` keys by `(peer_id, room_id)` and would
      accept a sibling's patch for room `7ADky` under the shared peer_id;
      `subscribe` is peer-keyed so the phone receives all 4 rooms' meta. The
      7ADky Pi did not re-auth during the 14:40-14:43 window.
- [ ] **OPEN (refined)**: does the extension ever send `room_meta_update`
      for a room the process did NOT register (a sibling room id)? If yes,
      the shared-peer_id path overwrites `7ADky`'s session_id — that is the
      h2 leak mechanism. If no, the rotation is the 7ADky Pi's own (h1).
      Needs the extension's debug log for the 14:40-14:43 window, OR a decoded
      ring-log `room_meta_updated` carrying room + session_id + peer.
- [ ] Decide fix path after the open question is resolved.
- [ ] A regression test once the root cause is confirmed.

## Out of scope

- The send-timeout / `room=main` outbound bug — separate story
  (`story-mobile-send-timeout-relay-room-main-mismatch`), likely same root.
- The dup/reorder identity fixes (landed).

## References

- Ring log: `debug/949-11f1-9243-4d82c1bdd26a.bin` — 7 sessions replayed,
  3 in the `14:40-14:43` window alone.
- Relay logs: 4 Pi auths from `l2X/dUc=` in 4 cwd-rooms
  (`7ADky8889NJy`, `SF_DCbXsmreE`, `zuMPC-YTtdUD`, `k0H-7lFh371e`).
- `app/lib/data/sync/sync_service.dart:569` — the session gate;
  `:844-846` — `SessionHistory` → `_replayHistory`;
  `:1199` — `replayDedup` (only fires after gate accepts).
- `app/lib/data/transport/connection_manager.dart:643` — `RoomAnnounced`
  handler; `:1012` — `_learnSessionFromPairOk`.
- `pi-extension/src/extension/owner_multiplexer.ts:450` — `broadcast` (all
  owners, no room filter).
- `pi-extension/src/session/sdk_session_projection.ts:638` —
  `maybeSendLateAttachSessionSync` (late-attach targets).
- `story-mobile-send-timeout-relay-room-main-mismatch` — likely same root
  (phone in `room=main`, Pis in cwd-rooms).
