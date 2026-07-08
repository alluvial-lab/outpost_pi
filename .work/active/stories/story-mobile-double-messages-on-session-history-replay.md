---
id: story-mobile-double-messages-on-session-history-replay
kind: story
stage: drafting
tags: [app, pi-extension, bug, transport, session]
parent: feature-reconnect-reproduction
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-07
updated: 2026-07-07
---

# Mobile shows double messages (user + agent) — `session_history` replays duplicating live frames

## Brief

The operator reports seeing **a lot of double messages (both user and agent
messages) on the mobile side.** This surfaced while verifying the subagent
chatlog-wipe fix (which is confirmed fixed and unrelated). It appears to be a
pre-existing symptom, not caused by the subagent work.

## What the capture shows (evidence, not inference)

A `REMOTE_PI_DEBUG_SEND=1` capture during a normal (non-subagent) turn shows
the phone receiving **`session_history` replays** on top of the live frames it
already received:

```
L147  queued_message_state          ← phone-initiated session_sync request
L148  session_history  events[30]   ← full 30-event replay (parent session id)
L150  queued_message_state          ← another session_sync request
L151  session_history  events[30]   ← another full 30-event replay
```

Both `session_history` frames:
- carry the **correct parent session id** (`019f3e03-...`) — NOT a session
  rotation or cross-session leak;
- carry `events[30]` — a full 30-event replay;
- are **phone-initiated** (preceded by `queued_message_state`, the reply to a
  `session_sync` the app sent);
- fire **after** the turn, `gateActive=false`.

So the phone is requesting `session_sync` and getting full replays. If the
app's replay dedup does not collapse these against the live frames it already
rendered, the same messages appear twice.

## What the capture does NOT show (explicitly out of scope)

- The operator also mentioned a message "wiped from my chat after you finished
  your turn." **The capture does not contain any frame that would reset the
  app's chat view** — no `room_meta_update({session_id})`, no `bye`, no session
  rotation. All `room_meta_update` frames after the turn carry only
  `working: true/false`. So the "wiped after turn" observation is **not
  explained by this capture** and is NOT part of this story. It may be an
  app-internal behavior on receiving a replay, a separate app-side bug, or
  something outside the extension→phone frame stream. The operator should
  re-report it separately if it recurs, with a fresh capture.

## Root cause (HYPOTHESIS — needs confirmation)

The extension's `session_sync` reply replays the full transcript event log
(`events[30]`) every time the phone asks. The app's replay path
(`_replayHistory` / `replayDedup` in `sync_service.dart`) is expected to dedup
against already-rendered live frames by `eventId`. If that dedup is failing
(or the live frames and replay frames derive different `eventId`s for the same
content), the phone renders both → doubles.

This is the same family as the original `story-mobile-cross-session-history-
leak` replay-dedup work, but now scoped to **same-session** replay duplication
(not cross-session leakage).

## Acceptance Criteria

- [x] Confirm the doubling mechanism: the replayed `session_history` events
      derived DIFFERENT `eventId`s from the live frames (live used random
      `uuid7()`; replay used deterministic `server:$sessionId:...`). Confirmed
      in `story-mobile-assistant-message-duplicated-live-replay` (same class,
      both assistant + user messages).
- [x] Determine whether the phone is requesting `session_sync` too eagerly:
      YES — three independent `requestSync` triggers fire near-simultaneously
      on chat-open/online: `_onlineActivated` (debounced 200ms,
      `sync_service.dart:540`), `chat_viewmodel._onStatus` (immediate on the
      online edge, `chat_viewmodel.dart:236`), and `chat_viewmodel._bootstrap`
      (immediate on chat open, `chat_viewmodel.dart:153`). Each sends a fresh
      `SessionSync` with a new id; the extension replies to each with a full
      `session_history`. `requestSync` does not dedupe in-flight requests.
- [x] Decide fix location: the identity fix (landed in
      `story-mobile-assistant-message-duplicated-live-replay`) makes the eager
      replays COLLAPSE — `replayDedup`'s `seenEventIds` set is seeded from
      `readSession` (which includes the live frames) and serialized via
      `_enqueue`, so the second replay's events are all `dropped:true` and
      `appendAll` skips them (Hive `containsKey` check). The double-request
      is wasteful (extra round-trips + dedup work) but no longer
      user-visible-harmful once the identity fix is deployed. The eager
      double-request itself is a low-priority perf/cleanliness follow-up
      (debounce/dedupe `requestSync`), NOT a blocker.
- [ ] DEPLOY + VERIFY: rebuild extension `dist/` + restart pi + sideload
      app APK; confirm a normal turn shows each message once even when
      chat is opened after the turn (triggering the eager replay).

## Out of scope

- The subagent chatlog wipe — FIXED
  (`story-extension-subagent-child-session-start-wipes-mobile-chat`).
- The subagent text leak + dispatch-prompt leak — FIXED
  (`story-extension-suppress-subagent-assistant-broadcast`).
- The "wiped after turn" observation — NOT in this story (see above); re-report
  separately if it recurs.

## References

- Capture: `/tmp/remote-pi-debug-send.jsonl` (2026-07-07, full-restart,
  `REMOTE_PI_DEBUG_SEND=1`) — `session_history` at L148/L151.
- `pi-extension/src/session/sdk_session_projection.ts` — `buildSessionHistoryMessage`
  / `forSession` (the replay source).
- `app/lib/data/sync/sync_service.dart:1199` — `replayDedup` (the dedup path);
  `:844-846` — `SessionHistory` → `_replayHistory`.
- Related: `story-mobile-cross-session-history-leak` (cross-session replay,
  ruled out as cross-room; this story is same-session duplication).
- Parent: `feature-reconnect-reproduction.md`.
