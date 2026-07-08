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

1. **The phone's WebSocket flaps too often.** A relay log sample from
   2026-07-08 shows ~25 connect/disconnect cycles in ~3 hours of testing,
   with sessions lasting 1–3 min before dropping. This is abnormal for an
   actively-used foreground app and suggests the app isn't holding the
   socket (no foreground service / wake lock, OS suspending the app, or
   the 20s WS ping interval being too aggressive a liveness probe for
   mobile).
2. **The identity fix is not robust to a dropped `agent_message(ts)` frame.**
   The deterministic-identity design assumes the live `agent_message(ts)`
   frame always reaches the phone. The fan-out suspend feature deliberately
   drops it when the peer is briefly offline, breaking that assumption.
   The fallback (random uuid) then dupes against the replay.

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

- [ ] **Confirm the flapping cause**: is the app requesting a foreground
      service / wake lock during active turns? If not, that's the primary
      fix. Check `app/android/app/src/main/AndroidManifest.xml` and any
      foreground service / wake lock code in `app/lib/`.
- [ ] **Quantify the flapping**: from the relay logs, measure the
      connect/disconnect cadence during active foreground use (not
      backgrounded). Is it every 1-3 min (abnormal) or only on backgrounding
      (expected)?
- [ ] **Layer 1 fix**: reduce the flap rate to acceptable (a foreground app
      in an active turn should not drop the socket). Verify with a relay
      log: connect/disconnect cycles during a 10-min active turn should be
      ≤1 (the initial connect).
- [ ] **Layer 2 fix**: a turn whose `agent_message(ts)` frame is dropped
      (simulated by killing the socket at `message_end`) does NOT produce a
      random-uuid fallback row that dupes against the replay. Either the
      fallback is suppressed (option A) or the identity is recovered from
      `agent_done` (option B) or re-broadcast (option C).
- [ ] Regression test: simulate a dropped `agent_message(ts)` mid-turn and
      assert the final rendered transcript has each assistant paragraph
      exactly once (no random-uuid dupe row).
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
