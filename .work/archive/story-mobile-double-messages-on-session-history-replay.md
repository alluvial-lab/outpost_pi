---
id: story-mobile-double-messages-on-session-history-replay
kind: story
stage: done
status: done
resolved_by: story-mobile-assistant-message-duplicated-live-replay
tags: [app, pi-extension, bug, transport, session]
parent: feature-reconnect-reproduction
depends_on: []
release_binding: v0.1.0
gate_origin: null
created: 2026-07-07
updated: 2026-07-21
verified_in_code: 2026-07-21
---

# Mobile shows double messages — `session_history` replay dedup (DIFFERENT class from the post-`/new` repro)

## ⚠️ Scope — read before investigating

This story documents a **specific, already-analyzed duplication mechanism**:
`session_history` replays arriving with eventIds that did not match the live
frames' eventIds, so `replayDedup` failed to collapse them and the phone
rendered both.

**This mechanism does NOT apply to the current post-`/new` repro.** The
clean repros captured on 2026-07-21 (`debug/4c2-11f1-ae25-659bdda1075d.bin`
and `debug/4c0-11f1-ae25-659bdda1075d.bin`) contain **zero `session_history`
frames** in the mobile log. Their duplication is the **delayed real `cli_`
echo arriving after the agent's turn** — a different mechanism, documented in
`story-mobile-stuck-message-after-new-session-replacement.md`.

**Do not route diagnostic agents to this story for the current repro.** This
story is retained as the record of the `session_history` class so it is not
re-opened when an agent greps for "duplicate" or "replay."

## Brief (original, 2026-07-07)

The operator reported seeing double messages (both user and agent messages)
on the mobile side while verifying the subagent chatlog-wipe fix (which is
confirmed fixed and unrelated). This appeared to be a pre-existing symptom,
not caused by the subagent work.

## What that capture showed (evidence, not inference)

A `REMOTE_PI_DEBUG_SEND=1` capture during a normal (non-subagent) turn showed
the phone receiving `session_history` replays on top of the live frames it
already received:

```
L147  queued_message_state          ← phone-initiated session_sync request
L148  session_history  events[30]   ← full 30-event replay (parent session id)
L150  queued_message_state          ← another session_sync request
L151  session_history  events[30]   ← another full 30-event replay
```

Both `session_history` frames carried the correct parent session id and
`events[30]` (a full replay), were phone-initiated (preceded by
`queued_message_state`, the reply to a `session_sync` the app sent), and
fired after the turn, `gateActive=false`.

## Root cause (confirmed for THIS class)

The extension's `session_sync` reply replays the full transcript event log
every time the phone asks. The app's replay path (`_replayHistory` /
`replayDedup` in `sync_service.dart`) dedups against already-rendered live
frames by `eventId`. The replayed `session_history` events derived
DIFFERENT `eventId`s from the live frames (live used random `uuid7()`;
replay used deterministic `server:$sessionId:...`), so `replayDedup` did not
collapse them and both were rendered.

This is the same family as the original `story-mobile-cross-session-history-
leak` replay-dedup work, scoped to same-session replay duplication (not
cross-session leakage).

## Fix status for THIS class

The identity fix landed in
`story-mobile-assistant-message-duplicated-live-replay` makes the eager
replays collapse — `replayDedup`'s `seenEventIds` set is seeded from
`readSession` (which includes the live frames) and serialized via
`_enqueue`, so the second replay's events are all `dropped:true` and
`appendAll` skips them (Hive `containsKey` check).

The eager double-`requestSync` itself (three triggers fire near-simultaneously
on chat-open/online: `_onlineActivated` debounced 200ms, `chat_viewmodel._onStatus`
immediate on the online edge, `chat_viewmodel._bootstrap` immediate on chat
open) is a low-priority perf/cleanliness follow-up (debounce/dedupe
`requestSync`), not a blocker — it is no longer user-visible-harmful once the
identity fix is deployed.

- [x] Confirm the doubling mechanism: replayed `session_history` events
      derived DIFFERENT `eventId`s from live frames. Confirmed in
      `story-mobile-assistant-message-duplicated-live-replay`.
- [x] Determine whether the phone requests `session_sync` too eagerly: YES
      (three triggers), but no longer user-visible-harmful post-identity-fix.
- [x] Decide fix location: identity fix (landed) collapses the eager replays.
- [ ] DEPLOY + VERIFY: rebuild extension `dist/` + restart pi + sideload
      app APK; confirm a normal turn shows each message once even when
      chat is opened after the turn (triggering the eager replay).

## Out of scope

- The subagent chatlog wipe — FIXED
  (`story-extension-subagent-child-session-start-wipes-mobile-chat`).
- The subagent text leak + dispatch-prompt leak — FIXED
  (`story-extension-suppress-subagent-assistant-broadcast`).
- **The current post-`/new` duplication** — different mechanism (delayed real
  `cli_` echo), see
  `story-mobile-stuck-message-after-new-session-replacement.md`.

## References

- Capture (this class): `/tmp/remote-pi-debug-send.jsonl` (2026-07-07,
  `REMOTE_PI_DEBUG_SEND=1`) — `session_history` at L148/L151.
- `pi-extension/src/session/sdk_session_projection.ts` — `buildSessionHistoryMessage`
  / `forSession` (the replay source).
- `app/lib/data/sync/sync_service.dart:1199` — `replayDedup` (the dedup path);
  `:844-846` — `SessionHistory` → `_replayHistory`.
- Related: `story-mobile-cross-session-history-leak` (cross-session replay,
  ruled out as cross-room; this story is same-session duplication).
- Parent: `feature-reconnect-reproduction.md`.
