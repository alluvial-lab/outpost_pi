---
id: story-mobile-connection-flapping-drops-identity-frames
kind: story
stage: drafting
tags: [app, pi-extension, bug, lifecycle, transport]
parent: feature-reconnect-reproduction
depends_on:
  - story-extension-suspend-fanout-on-peer-offline
  - story-mobile-assistant-message-duplicated-live-replay
release_binding: null
gate_origin: null
created: 2026-07-08
updated: 2026-07-07
---

# Mobile connection flapping drops the deterministic identity frame → dupes

## Brief

The phone's relay WebSocket flaps every 1–3 minutes during active use —
connect, disconnect (relay `disconnected`), reconnect (relay `authenticated`,
`superseded_existing=false`). This is normal mobile behavior (backgrounding,
Doze, wifi power-saving, app-suspend reclaiming the socket), but it now has
a user-visible cost: it drops the deterministic `agent_message(ts)` frame
the identity fix depends on, which re-opens the duplicate-message bug the
identity fix was meant to close.

### The mechanism (confirmed 2026-07-08)

The assistant-message identity fix (`story-mobile-assistant-message-
duplicated-live-replay`, decision 1) makes `message_end` the single source of
live assistant identity: the extension broadcasts `agent_message(ts,
message_id)` at `message_end`, and the app derives the same deterministic
`eventId`/`messageId` as the `session_history` replay path so the two collapse
to one Hive row.

But the extension's `OwnerMultiplexer.broadcast()` **skips offline peers**
(`story-extension-suspend-fanout-on-peer-offline`): when the relay marks the
phone offline (`peer_offline`), `broadcast()` does `if
(this.offlinePeerIds.has(peerId)) continue;` — the frame is dropped, not
queued. So if the phone's connection flaps during the `message_end`→
`tool_execution_start` window, the `agent_message(ts)` frame is dropped:

1. Agent produces a turn. `message_end` fires → extension broadcasts
   `agent_message(ts, message_id)`.
2. **The phone's connection flaps in that instant.** The relay marks the peer
   offline; `broadcast()` skips it. The `agent_message(ts)` frame is lost.
3. The phone reconnects. `tool_execution_start` → `ToolRequest` arrives (and/or
   `agent_end` → `AgentDone` arrives). Since the phone never received
   `agent_message(ts)`, `_agentMessageCommittedThisTurn` is false.
4. The `ToolRequest`/`AgentDone` handler commits the streamed buffer with the
   **legacy random `uuid7()`** eventId/messageId (the fallback path).
5. On reconnect the phone requests `session_sync` → gets the replay with the
   **deterministic** eventId. Random-uuid live row + deterministic replay row
   = two Hive rows, two different ids → **visible duplicate bubble**.

The `ToolRequest` flush guard added 2026-07-08
(`_agentMessageCommittedThisTurn` check) and the `AgentDone` guard only help
when the deterministic `agent_message(ts)` **arrives**. When it's dropped by
the suspend, both guards fall through to the random-uuid fallback → dupe.

### Why this is the flapping twin, not the slow-recovery twin

Distinct from the existing backlog:
- `idea-mobile-drop-slow-recovery` — ~5min end-to-end recovery after a
  wifi→cellular switch (recovery latency).
- `idea-mobile-drop-half-open-tcp` — no clean FIN on network switch;
  duplicate-connection takeover by ping timeout.

This story is about **frequent flapping during active use** (not a one-time
network transition) and its **specific consequence**: dropping the
identity frame that the dupe fix depends on. The flapping itself is
mobile-platform behavior; the bug is that the system isn't robust to it.

## Root cause (two layers)

### Layer 1 — the flapping (CONFIRMED 2026-07-08)

**The app's WS-level ping interval (20s) is tighter than the relay's (25s),
so the app tears down connections the relay still considers alive.** The
`IOWebSocketChannel.connect(pingInterval: 20s)` (`ws_transport.dart:82`)
sends a WS Ping every 20s and closes the socket with `goingAway` if the pong
isn't received within 20s. The relay sends its own keepalive ping every 25s
(`relay/src/handlers/peer.rs:130`). On mobile, a momentary network blip
(cell handoff, wifi roaming, Doze micro-sleep, transient latency) causes a
missed pong → the app closes the socket → `onDone` → `_onChannelLost` →
`_scheduleRetry` → reconnect. The relay, still within its own 25s window,
hasn't noticed the peer is gone — so the reconnect often hits
`superseded_existing=true` (a duplicate-auth takeover).

**Three overlapping connections in 12 seconds** (relay log 05:18:11 →
05:18:17 → 05:18:23, each `superseded_existing=true`) confirm a reconnect
storm: `onAppFrameObserved()` resets the backoff to attempt 0 on any inbound
frame, so a brief connection that gets a frame or two → reset → 1s retry →
brief connection → reset → 1s retry. The 1s/2s/5s/10s/30s backoff
(`reachability.dart`) never ramps because it keeps resetting.

**No foreground service / wake lock** is declared in `AndroidManifest.xml`
(only `INTERNET`, `ACCESS_NETWORK_STATE`, `RECORD_AUDIO`, `CAMERA`). This
matters for genuine backgrounding (screen-off / app-switched), but the
flapping during *active foreground use* is the ping interval, not
backgrounding — the 9s/6s disconnects are too short for Doze.

### Layer 2 — the identity fix is not robust to a dropped `agent_message(ts)` frame

Even with reduced flapping, a mobile socket will sometimes drop mid-turn. The
identity fix must not depend on a single frame arriving. Options:

- **(A) Re-emit dropped identity frames on reconnect.** When the phone
  reconnects and requests `session_sync`, the extension already replays the
  full transcript via `session_history`. The app's `replayDedup` collapses
  deterministic-id rows. So if the **live fallback didn't commit a random-uuid
  row**, the replay alone would render correctly. The fix: when
  `agent_message(ts)` was dropped (phone was offline at `message_end`), the
  app should **not** commit the buffer with a random uuid — it should leave
  the buffer uncommitted and let the reconnect replay fill it
  deterministically. This means the `ToolRequest`/`AgentDone` fallback needs
  to know whether a deterministic `agent_message` *should have* arrived
  (i.e., the extension is the fixed version) vs. a legacy extension that
  never sends one.
- **(B) Carry identity on `agent_done` too.** The extension's `agent_end`
  broadcast (`index.ts:1414`) currently sends `agent_done` without `ts`/
  `message_id`. If `agent_done` carried the same stable identity as
  `agent_message`, the app could derive the deterministic eventId from
  `agent_done` even when `agent_message` was dropped. The schema already has
  optional `ts` on `agentDone` (added by the identity fix); populate it.
  This doesn't help the `ToolRequest` flush (which fires before `agent_end`),
  but it closes the `AgentDone` fallback.
- **(C) Extension re-broadcasts on `peer_online`.** When the phone
  reconnects (`peer_online`), the extension could re-broadcast the current
  turn's `agent_message(ts)` if the turn is still active or recently ended.
  This is a queue-of-one (the last identity frame), not unbounded queueing,
  so it doesn't violate the suspend feature's drop-don't-queue design.

**Recommendation:** Layer 1 (increase the WS ping interval) is the primary
fix — it addresses the root cause (the app tearing down live connections).
Layer 2 is defense-in-depth and can ship separately. Decide the exact
Layer 2 option at design time.

## Fix options (decide at design time)

### Layer 1 — reduce the flapping (app-side)

- **Foreground service / wake lock** while a turn is active or the app is
  foregrounded, so Android doesn't suspend the socket mid-turn. This is the
  platform-correct fix for "active remote-coding session must not be
  suspended." Verify whether `app/` already requests a foreground service
  or partial wake lock; if not, this is the primary fix.
- **Tune the WS ping interval** (`ws_transport.dart:82`,
  `pingInterval: 20s`). 20s may be too aggressive for mobile (a momentary
  network blip kills the socket). Consider a longer interval or
  platform-aware liveness. Cross-check against `idea-mobile-drop-half-open-tcp`
  (25s relay ping) — the app's 20s is tighter than the relay's 25s.
- **Backoff / reconnect-smoothing**: a brief flap should not fully tear down
  and re-establish the authed connection if a reconnection is imminent.
  Confirm whether `ConnectionManager` has a grace period before declaring
  the channel lost.

### Layer 2 — make the identity fix robust to dropped frames (extension/app-side)

Even with reduced flapping, a mobile socket will sometimes drop mid-turn. The
identity fix must not depend on a single frame arriving. Options:

- **(A) Re-emit dropped identity frames on reconnect.** When the phone
  reconnects and requests `session_sync`, the extension already replays the
  full transcript via `session_history`. The app's `replayDedup` collapses
  deterministic-id rows. So if the **live fallback didn't commit a random-uuid
  row**, the replay alone would render correctly. The fix: when
  `agent_message(ts)` was dropped (phone was offline at `message_end`), the
  app should **not** commit the buffer with a random uuid — it should leave
  the buffer uncommitted and let the reconnect replay fill it
  deterministically. This means the `ToolRequest`/`AgentDone` fallback needs
  to know whether a deterministic `agent_message` *should have* arrived
  (i.e., the extension is the fixed version) vs. a legacy extension that
  never sends one.
- **(B) Carry identity on `agent_done` too.** The extension's `agent_end`
  broadcast (`index.ts:1414`) currently sends `agent_done` without `ts`/
  `message_id`. If `agent_done` carried the same stable identity as
  `agent_message`, the app could derive the deterministic eventId from
  `agent_done` even when `agent_message` was dropped. The schema already has
  optional `ts` on `agentDone` (added by the identity fix); populate it.
  This doesn't help the `ToolRequest` flush (which fires before `agent_end`),
  but it closes the `AgentDone` fallback.
- **(C) Extension re-broadcasts on `peer_online`.** When the phone
  reconnects (`peer_online`), the extension could re-broadcast the current
  turn's `agent_message(ts)` if the turn is still active or recently ended.
  This is a queue-of-one (the last identity frame), not unbounded queueing,
  so it doesn't violate the suspend feature's drop-don't-queue design.

**Recommendation:** Layer 1 (foreground service) is the primary fix — it
addresses the root cause (flapping). Layer 2 option (A) or (B) is the
defense-in-depth — even with a foreground service, mobile sockets
occasionally drop, and the identity fix should not hard-fail to random uuids.
Decide the exact Layer 2 option at design time; (A) is cleanest (no new wire
fields, just "don't commit random uuids when deterministic is expected") but
needs a way to know the extension version; (B) is additive and lower-risk.

## Acceptance Criteria

- [x] **Confirm the flapping cause**: the app's WS-level ping interval (20s,
      `ws_transport.dart:82`) is tighter than the relay's (25s,
      `relay/src/handlers/peer.rs:130`), so the app tears down connections
      the relay still considers alive. Mobile network blips → missed pong →
      `goingAway` close → reconnect storm. Confirmed by relay log showing
      3 overlapping auths in 12s (`superseded_existing=true`).
- [x] **No foreground service / wake lock**: `AndroidManifest.xml` declares
      only INTERNET, ACCESS_NETWORK_STATE, RECORD_AUDIO, CAMERA. The flapping
      during active foreground use is the ping interval, not backgrounding.
      (A foreground service is still valuable for genuine backgrounding, but
      that's a separate concern — the flapping happens in the foreground.)
- [x] **Layer 1 fix**: increase the WS ping interval to at least match the
      relay's 25s (preferably longer for mobile tolerance), so the app
      doesn't tear down connections the relay still considers alive. Verify
      with a relay log: connect/disconnect cycles during a 10-min active
      foreground turn should drop significantly.
  - **DONE 2026-07-08**: bumped `ws_transport.dart:82` from 20s to 45s
    (deliberately looser than the relay's 25s). 670/670 tests pass, analyze
    clean. APK rebuilt. Needs sideload + a relay-log verification that the
    flap rate drops (the 9s/6s disconnects and 3-auths-in-12s storms should
    stop).
- [ ] **Layer 2 fix** (defense-in-depth, can ship separately): a turn whose
      `agent_message(ts)` frame is dropped does NOT produce a random-uuid
      fallback row that dupes against the replay. Either the fallback is
      suppressed (option A) or the identity is recovered from `agent_done`
      (option B) or re-broadcast (option C).
- [ ] Regression test (Layer 2): simulate a dropped `agent_message(ts)`
      mid-turn and assert the final rendered transcript has each assistant
      paragraph exactly once.
- [ ] `flutter analyze` + `flutter test` clean; `corepack pnpm typecheck` +
      `corepack pnpm test` clean (whichever side the fix lands on).

## Out of scope

- The slow-recovery latency (`idea-mobile-drop-slow-recovery`) — that's a
  one-time network-transition recovery speed issue, not frequent flapping.
- The half-open TCP detection (`idea-mobile-drop-half-open-tcp`) — that's
  about detecting a dead path, not preventing the flap.
- The fan-out suspend feature itself (`story-extension-suspend-fanout-on-
  peer-offline`) — it's working as designed (dropping frames for offline
  peers). This story is about making the *identity fix* robust to that
  drop, and reducing the flap rate so the drop rarely matters.
- The fan-out telemetry noise (fixed 2026-07-08 — removed the `sendMessage`
  injection; now `console.warn` only).

## References

- Relay logs: `docker logs remote-pi-relay` — ~25 connect/disconnect cycles
  for peer `ENBP7YI=` across 2026-07-08 00:52–03:38 UTC.
- `app/lib/data/transport/ws_transport.dart:82` — `pingInterval: 20s`.
- `app/lib/data/transport/ws_transport.dart:308-315` — `send()` stamps
  `room: _activeRoom`.
- `app/lib/data/transport/connection_manager.dart` — reconnect/backoff
  state machine.
- `pi-extension/src/extension/owner_multiplexer.ts:450-456` — `broadcast()`
  skips offline peers (the drop).
- `pi-extension/src/index.ts:1398-1414` — `agent_end` broadcast (no `ts`).
- `app/lib/data/sync/sync_service.dart:608-640` — `AgentDone` buffer-commit
  fallback (random uuid when `_agentMessageCommittedThisTurn` is false).
- `app/lib/data/sync/sync_service.dart:768-805` — `ToolRequest` flush (now
  guarded, but falls through to random uuid when the guard is false).
- Parent: `feature-reconnect-reproduction.md`.
- Depends on: `story-extension-suspend-fanout-on-peer-offline` (the drop
  mechanism), `story-mobile-assistant-message-duplicated-live-replay` (the
  identity fix this regressions against).
- `.agents/skills/mobile-remote-coding/SKILL.md` — "do not rely on mobile
  background WebSocket continuity for correctness."
- `.agents/skills/flutter-mobile/SKILL.md` — Android background restrictions,
  `AppLifecycleListener`.
