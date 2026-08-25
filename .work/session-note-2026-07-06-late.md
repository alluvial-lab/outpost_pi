# Session note: 2026-07-06 (late) — identity fixes landed + 2 new bugs scoped

## Landed this session (all reviewed, all green: app 668/668, ext 754/754)

1. **Reorder fix** (`ca555be`) — `story-fix-transport-active-room-reestablishment-on-reconnect`
   (stage: review, APPROVED ×2). `WsTransport` constructed with correct `activeRoom` from
   `connect()`; `adopt()` mirrors `_connect`. Inbound demux race eliminated.

2. **Dup amplification** (`4be50e7`) — `story-mobile-assistant-message-duplicated-live-replay`
   decision 2. `ToolRequest` re-flush synchronous buffer clear.

3. **Identity source (a) assistant** (`78bad9c` + `e359e39`) — same story, decision 1.
   Extension `message_end` broadcasts live `agent_message` with stable `(ts, message_id)`;
   app derives deterministic eventId matching replay. **Multi-block collision fix** (`e359e39`)
   addressed a REJECT from deep review: use `messageId ?? inReplyTo` as stable key so
   multi-block messages don't collide. Second-pass review: APPROVE.

4. **Identity source (a) user-message** (`784227e`) — same story, user-message follow-up.
   Extension `message_end` (user branch) broadcasts live `user_input` with `ts`; app `UserInput`
   handler derives deterministic eventId. Event-store convergence (projection already deduped
   by `ChatMessage.id`). Codegen interface-collision bug found+fixed (Client+Server
   `user_message` share `UserMessage` interface; `ts` needed on both schemas).

   Both stories at stage: review, fully reviewed.

## Two NEW bugs scoped from the 2026-07-06 clean repro (ring log `debug/949-...bin`, gitignored)

### Bug 1: send-timeout / `room=main` (`story-mobile-send-timeout-relay-room-main-mismatch`, stage: drafting)
- CONFIRMED via relay logs: phone's outbound envelopes carry `room=main` while app believes
  `7ADky`. Relay can't find a Pi in `main` → drops → 20s `send_timeout` → "not delivered".
- This is the SEND-side twin of the reorder bug (inbound demux). Same root: `WsTransport._activeRoom`
  stuck at `'main'`. The reorder fix (`ca555be`) addresses it but **is not deployed** (source
  commits only; phone runs old APK). Plus `peer.roomId ?? 'main'` fallback still sends to `main`
  when PeerRecord has no room.
- The workstation's `[remote-pi] fanout-presence: Pi rejected message: agent session not bound yet`
  is a SEPARATE stacked layer (extension's `sendMessage` for fanout-presence customType failing
  because `messageApi` is null — recoverable, should be silenced/queued).
- **Fix**: deploy the reorder fix + harden `peer.roomId == null` path (queue sends vs send to `main`).

### Bug 2: cross-session leak (`story-mobile-cross-session-history-leak`, stage: drafting, AMBIGUOUS)
- Operator reports skills/ and starmods/ sessions appearing in the remote_pi mobile chat.
- Ring log: `_activeRef.sessionId` changed 5 times in 3 min while `_activeRoomId` stayed `7ADky`.
- **Operator confirmed NOT running `/new`/`/resume`** at the time (08:40-08:43 AM mountain) — just
  woke up to check sessions and send a response. So hypothesis (1) (own session rotation) is unlikely.
- Static trace found NONE of the 3 room handlers can mutate room `7ADky`'s `sessionId` from a
  sibling room's announcement — they all key by `roomId`. The relay doesn't mis-route
  `room_meta_updated` across rooms.
- **Key unresolved evidence**: the `rooms` snapshot's `7ADky` entry appears to carry different
  sessions over time (`c12db9c7`, `06c8acbf`, `96bc2b30`), which `activeSessionId` reads and
  `activate()` flips `_activeRef` to. But the relay keys rooms by `(peer_epk, room_id)` and each
  of the 4 Pis registers only its own cwd-room — so `7ADky`'s entry should carry the `7ADky` Pi's
  session only.
- **The mutation path that flips `_activeRef`**: `_onRoomsChanged` (`sync_service.dart:544-554`)
  → `_resolveActiveRef` → `activeSessionId` (`connection_manager.dart:240-247`) reads
  `RoomInfo.sessionId` for the active room. If the `rooms` snapshot's `7ADky` entry carries a
  sibling's session, `activate()` flips to it. BUT the static trace says the snapshot can't mutate
  `7ADky` from a sibling — so either (a) the `7ADky` Pi's session genuinely rotated (needs
  operator confirmation of daemon restarts/autopilot `/new`), or (b) the relay's room registry
  is somehow stamping a sibling's session on `7ADky` (needs relay room-state inspection).
- **Two fixes identified** (both needed eventually):
  - App-side (primary): `_onRoomsChanged` must not `activate()` to a session that differs from
    the user's chosen chat without explicit user action.
  - Extension-side (defense in depth): `OwnerMultiplexer.broadcast` (`owner_multiplexer.ts:450-454`)
    has no room filter — sibling Pis broadcast to ALL owners. Requires per-owner room tracking.
- **Parked at stage: drafting** — implementing on the wrong hypothesis risks breaking correct
  reconnect-hydration. Needs either a decoded-payload repro (ring log decoding
  `room_meta_updated` room+session_id and `session_history` wire session_id) OR relay room-state
  inspection to confirm whether `7ADky`'s session is genuinely rotating or being overwritten.

## Next steps (priority order)
1. **Bug 1 (send-timeout)**: rebuild + sideload the app with the reorder fix; confirm the relay
   no longer logs `room=main` for the phone. Then harden `peer.roomId == null`.
2. **Bug 2 (cross-session leak)**: inspect the relay's current room registry
   (`docker exec remote-pi-relay` + the `mesh.db` SQLite, or add a relay admin endpoint) to see
   what session_id is stamped on room `7ADky` for the owner epk. If it's rotating without operator
   action, investigate why (daemon supervisor? autopilot?). If it's a sibling's session, find
   the relay path that overwrites it. THEN implement the app-side fix.
3. Both reviewed stories (reorder, dup) are at stage: review — ready for a final review pass or
   release binding when the operator wants to ship.

## Key files
- `app/lib/data/sync/sync_service.dart` — `activate()`, `_onRoomsChanged`, `_replayHistory`,
  `UserInput`/`AgentMessage`/`AgentDone` handlers, `_agentMessageCommittedThisTurn`.
- `app/lib/data/transport/connection_manager.dart` — `activeSessionId`, `RoomAnnounced`/
  `RoomMetaUpdated`/`RoomsSnapshot` handlers, `_maybeAdoptLegacyRoom`, `adopt`, `_connect`.
- `app/lib/data/transport/ws_transport.dart` — `_activeRoom`, `connect(activeRoom:)`, demux.
- `pi-extension/src/session/sdk_session_projection.ts` — `appendLegacySdkMessageToTranscript`
  (broadcasts live `agent_message`/`user_input` with stable ts), `wakeAgent`, `messageApi`.
- `pi-extension/src/extension/owner_multiplexer.ts:450-454` — `broadcast` (no room filter).
- `relay/src/peers/rooms.rs` — `rooms_of`, `apply_patch` (keyed by `(peer_id, room_id)`).
- Ring log: `debug/949-11f1-9243-4d82c1bdd26a.bin` (gitignored, NDJSON).
