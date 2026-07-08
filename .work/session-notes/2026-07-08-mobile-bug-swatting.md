# Session note — 2026-07-08 (mobile bug-swatting)

## Goal

Drain usability bugs: failed sends from mobile (blocker) + double messages
in mobile chat. Operator reported both as annoying; the first was a full-on
blocker.

## What shipped (5 fixes, all verified live on phone)

### Bug 1 — Failed sends from mobile (THE BLOCKER)
**Root cause**: `WsTransport._activeRoom` stuck at the `'main'` default.
`send()` stamps `room: _activeRoom` (`ws_transport.dart:312`) — the same
field the inbound demux compares against. So sends routed to `'main'`
(no Pi there) → no echo → 20s `send_timeout`. Same field caused the 77%
inbound demux drop rate (8,640 dropped frames in one capture).
**Fix**: `80b04e5` (already in source from prior session) — construct
`WsTransport` with `activeRoom: peer.roomId ?? 'main'` from frame 1.
**Verified**: zero `room-mismatch` drops on relay; correct room
`7ADky8889NJy` on all frames.

### Bug 2a — `ToolRequest` flush dupe (pre-tool narration)
**Root cause**: the `ToolRequest` handler flushed the streaming buffer with
random `uuid7()` eventId/messageId, but the SDK fires `message_end`
(→ deterministic `agent_message(ts)` broadcast) BEFORE
`tool_execution_start` (→ `ToolRequest`). So the deterministic commit
landed first, then the flush re-committed the same text under a random id
→ second Hive row → dupe. The `AgentDone` handler had the
`_agentMessageCommittedThisTurn` guard; `ToolRequest` did not.
**Fix**: added the guard to the `ToolRequest` flush.
**Verified**: pre-tool narration text appears once.

### Bug 2b — Workstation user-message dupe (TUI-typed messages)
**Root cause**: a message typed in the Pi TUI produced TWO `user_input`
broadcasts with incompatible ids — `pi.on("input")` (id=`turnId`, no ts)
and `message_end` (id=`sync_<ts>`, with ts). The identity fix added the
`message_end` broadcast but never removed the pre-existing input-handler
broadcast.
**Fix**: removed the `pi.on("input")` `user_input` broadcast entirely;
`message_end` owns it (fires milliseconds later, before agent streaming).
**Verified**: TUI-typed message appears once on phone.

### Bug 3 — Fan-out telemetry noise (TUI spam + agent responding)
**Root cause**: `onFanoutPresenceChanged` called `_sendPiMessage`
(display:false), which routed through `sendCustomMessage` →
`appendCustomMessageEntry`, injecting the fan-out text into the agent's
conversation as a `custom` message. The agent saw it and responded to it
("Re: the repeated my/xN94M fan-out suspensions..."). `display:false` only
suppresses the TUI bubble render, NOT entry into the agent context.
First fix (`console.warn`) also failed: pi surfaces extension
`console.warn` to the TUI as a notification (`runner.js:297`).
**Fix**: made the handler fully silent (no `_sendPiMessage`, `_notify`,
or `console.warn`). The suspend/resume *behavior* (skipping offline peers
in `broadcast()`) is unchanged.
**Verified**: TUI quiet; agents stop responding to fan-out notifications.

### Bug 4 — Mobile connection flapping (20s ping → 45s)
**Root cause**: the app's WS-level `pingInterval` (20s) was tighter than
the relay's own keepalive (25s), so the app tore down connections the
relay still considered alive. A single missed pong (mobile network blip)
→ `goingAway` close → `_onChannelLost` → reconnect storm.
`onAppFrameObserved()` resets the backoff to 1s on any inbound frame, so
brief connections kept the backoff from ramping → 3 overlapping auths in
12s (`superseded_existing=true`). NOT backgrounding (9s/6s disconnects too
short for Doze; no foreground service declared, but that's a separate
concern for genuine backgrounding).
**Fix**: bumped `ws_transport.dart:82` from 20s to 45s (deliberately
looser than the relay's 25s).
**Verified**: 6 minutes stable foreground connection, zero flaps (was
every 1-4 min before).

## What's still open (low priority)

- **Layer 2 identity robustness** (`story-mobile-connection-flapping-drops-
  identity-frames`, still `drafting`): if a flap hits during the
  `message_end`→`tool_execution_start` window, the `agent_message(ts)`
  frame is dropped → random-uuid fallback → dupe against replay. The
  ping fix reduces this dramatically (flaps are now rare), but the edge
  case remains. Options A/B/C scoped in the story; can ship separately.
- **Stale Hive rows** (deferred migration): pre-fix phones may have
  duplicate rows with random eventIds that persist until the box is
  cleared. The next replay doesn't clear them (deterministic id doesn't
  match random id). A one-time dedup pass on `activate()` was deferred.
  Fresh installs (this operator's case) are unaffected.
- **Foreign-session `session_mismatch`** (`story-foreign-session-user-
  message-tolerance`, `drafting`): cross-process duplicate delivery to a
  pi with a different `session_id` still surfaces a visible ⚠ error.
  Needs design (can't blindly tolerate `session_mismatch` — it's the
  re-sync signal).
- **Eager double `session_sync`** (`story-mobile-double-messages-on-
  session-history-replay`, `drafting`): three `requestSync` triggers fire
  near-simultaneously on chat-open/online. Now harmless (collapses via
  dedup) but wasteful. Low-priority perf follow-up.

## Deploy state

- **App APK** (v1.2.0+7): rebuilt with all app-side fixes (ToolRequest
  guard, ping interval 45s). Operator sideloaded; verified.
- **Extension `dist/`**: rebuilt with all extension-side fixes
  (fan-out silent, workstation user_input broadcast removed). Operator
  restarted pi; verified.
- **Relay**: no change (0.2.0, healthy).

## Key lesson (for the next session)

The identity-fix family has a recurring failure mode: **adding a new
deterministic-identity broadcast without removing the pre-existing
random-id broadcast** → two rows → dupe. This happened for assistant
messages (ToolRequest flush), user messages (input handler), and almost
for the early delivery-time echo. When adding a deterministic path, audit
for and remove the legacy path it replaces. The `message_end` hook is the
single source of live identity — anything else that broadcasts
`agent_message`/`user_input` with a different id scheme is a dupe source.

Also: `console.warn` in an extension is NOT silent — pi surfaces it to the
TUI. Use truly silent paths (no output) for operational telemetry that
fires on mobile connection flaps.

## Commits

- `b747d26` scope: story-mobile-connection-flapping-drops-identity-frames
- `1c92419` fix(pi-extension): remove duplicate user_input broadcast
- `5679a29` fix(pi-extension): make fan-out suspend/resume fully silent
- `40f2f33` fix(app): bump WS ping interval 20s→45s
- (`80b04e5` was prior session; verified this session)
