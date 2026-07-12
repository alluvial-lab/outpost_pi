---
id: story-mobile-connection-flapping-drops-identity-frames
kind: story
stage: done
tags: [app, pi-extension, bug, lifecycle, transport]
parent: feature-reconnect-reproduction
depends_on:
  - story-extension-suspend-fanout-on-peer-offline
  - story-mobile-assistant-message-duplicated-live-replay
release_binding: v0.1.0
gate_origin: null
created: 2026-07-08
updated: 2026-07-08
review_addressed: 2026-07-08
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

## Design decision (2026-07-08) — Layer 2 option (A): suppress the random-uuid fallback when deterministic identity was expected

**Chosen: (A).** A sticky capability flag latched `true` the first time a
live `AgentMessage` with `ts != null` arrives (the fixed extension's
`message_end`-driven broadcast). Once latched, a turn that reaches
`ToolRequest`/`AgentDone` flush with `_agentMessageCommittedThisTurn == false`
means the deterministic `agent_message(ts)` frame was **dropped** mid-flap
(relay suspend for an offline peer), NOT a legacy extension that never sends
one. Suppress the random-uuid `AssistantMessageCommitted` commit in that case
and clear the streaming buffer; the reconnect `session_sync` replay fills the
row deterministically (a random-uuid live row would dupe against it — random
id vs deterministic id, no `replayDedup` collapse).

**Why (A) over (B) and (C):**
- **(B) carry identity on `agent_done`** is flawed for this case. The
  `agent_end` handler has no access to the `message_end` `ts` (it would
  stamp `Date.now()` at agent_end time, which is NOT the replay's `ts`), so
  even populating `agent_done.ts` would not produce a dedup-collapsing
  eventId. It also does not cover the `ToolRequest` flush path (which fires
  before `agent_end`). It would only close the `AgentDone` fallback, and
  weakly. (A) closes both paths with no wire change.
- **(C) re-broadcast on `peer_online`** adds an extension-side queue-of-one
  and a new code path; (A) is strictly simpler (app-side suppression, no
  extension change, the replay already does the backfill).
- **(A) vs extension-version probing:** the story noted (A) "needs a way to
  know the extension version." The sticky capability flag IS that probe — the
  first observed `agent_message(ts)` is the version signal, no wire
  capability field needed. Legacy extensions never send `ts`, so the flag
  stays false and the fallback remains intact (verified by counter-test).

**Behavior preservation:** for a legacy extension that never sends
`agent_message(ts)`, the flag stays false → the random-uuid fallback
commits exactly as before (covered by a regression/counter-test). The fix is
strictly additive: it only changes behavior once the fixed extension has been
observed at least once.

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
- [x] **Layer 2 fix** (defense-in-depth, can ship separately): a turn whose
      `agent_message(ts)` frame is dropped does NOT produce a random-uuid
      fallback row that dupes against the replay. Either the fallback is
      suppressed (option A) or the identity is recovered from `agent_done`
      (option B) or re-broadcast (option C).
  - **DONE 2026-07-08**: option (A) — sticky `_extensionSendsDeterministicAgentMessage`
    capability flag latched on first `AgentMessage(ts != null)`; suppresses the
    random-uuid fallback in `AgentDone` and `ToolRequest` when latched but no
    commit arrived this turn. Buffer is cleared; reconnect replay fills.
- [x] Regression test (Layer 2): simulate a dropped `agent_message(ts)`
      mid-turn and assert the final rendered transcript has each assistant
      paragraph exactly once.
  - **DONE 2026-07-08**: added `dropped agent_message(ts) mid-flap: ToolRequest/
    AgentDone suppress random-uuid fallback; replay fills deterministically` +
    counter-test `legacy extension (no agent_message(ts) ever): AgentDone still
    commits the streamed buffer`. Both pass.
- [x] `flutter analyze` + `flutter test` clean; `corepack pnpm typecheck` +
      `corepack pnpm test` clean (whichever side the fix lands on).
  - **DONE 2026-07-08**: `flutter analyze` clean (0 issues); `flutter test
    test/data/sync/sync_service_test.dart` 69/69 pass (app-side only — no
    extension change). Layer 1 relay-log verification still pending a live
    phone session.

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

## Implementation notes

- **Files changed:**
  - `app/lib/data/sync/sync_service.dart` — added
    `_extensionSendsDeterministicAgentMessage` sticky capability flag; latch
    it in the `AgentMessage(ts != null)` branch; suppress the random-uuid
    `AssistantMessageCommitted` fallback in both the `AgentDone` and
    `ToolRequest` flush paths when the flag is latched but
    `_agentMessageCommittedThisTurn` is false.
  - `app/test/data/sync/sync_service_test.dart` — added the dropped-frame
    regression test + the legacy-extension counter-test.
- **Tests added:**
  - `dropped agent_message(ts) mid-flap: ToolRequest/AgentDone suppress
    random-uuid fallback; replay fills deterministically`
  - `legacy extension (no agent_message(ts) ever): AgentDone still commits
    the streamed buffer`
- **Verification:** `flutter analyze` (0 issues); `flutter test
  test/data/sync/sync_service_test.dart` (69/69 pass, including the 2 new).
- **Discrepancies from design:** none. The design's concern that option (A)
  "needs a way to know the extension version" is resolved by the sticky
  capability flag itself (first observed `agent_message(ts)` = the version
  signal); no wire capability field was needed.
- **Edge cases handled:**
  - Legacy extension (never sends `ts`): flag stays false → fallback
    commits as before (counter-test).
  - First-ever turn is the dropped one: flag is not yet latched → fallback
    commits (random uuid). This is correct for a brand-new pairing whose very
    first turn drops — there's no prior evidence the extension sends `ts`, so
    we can't distinguish legacy from dropped. The dupe risk is one turn on a
    fresh pairing; subsequent turns are protected. Acceptable.
  - Buffer UI: on suppression the streaming buffer clears (UI hides the
    in-flight text) until the reconnect replay backfills. Reconnect
    `requestSync` is guaranteed on every reconnect (`_onlineActivated` →
    200ms debounce → `SessionSync`), so the gap is brief.
- **Adjacent issues parked:** none.
- **Still open (NOT this story's Layer 2):** Layer 1 live verification
  (relay-log flap rate after the 45s ping sideload) needs a live phone
  session; the phone was offline at review time. The Layer 2 code fix does
  not depend on that verification.

## Review findings (2026-07-08, cross-model `openai-codex/gpt-5.5`)

Standard-lane code review returned `Request changes` with 1 blocker + 1
important, both addressed:

- **Blocker (resolved): capability flag was process-global.**
  `_extensionSendsDeterministicAgentMessage` was latched once for the whole
  `SyncService` and never reset. If peer A (fixed extension) latched it,
  then the app switched to a legacy peer B, B's `AgentDone`/`ToolRequest`
  fallback would be wrongly suppressed → real text lost. The design claim
  "legacy extensions keep the fallback" was only true per-peer, not globally.
  **Fix:** reset the flag in `activate()` on a genuine session switch, so the
  capability is per-active-session (re-latched on the first
  `agent_message(ts)` from THIS session). Regression test added:
  `capability flag is per-session: prior fixed peer does not suppress a later
  legacy peer's fallback`.
- **Important (resolved): reconnect backfill not unconditional.**
  `requestSync()` parks a pending request when `_activeRef` is null, but
  `activate()` did not drain it after binding a ref — so a suppressed-row
  turn whose reconnect fired before the session id was known would never
  get its replay backfill. **Fix:** drain `_pendingSyncRequest` in
  `activate()` after a non-null ref binds. The implementation notes' claim
  "guaranteed on every reconnect" is now accurate.
