# Session note — 2026-07-05/06 — observability feature complete + reconnect cluster attributed

Transient handoff note. Per `.agents/rules/agent-discipline.md` this lives in
`.work/` (transient) and is NOT a durable artifact. Delete when superseded.

## What shipped this session

Continued the `epic-targeting-and-session-lifecycle-contracts` critical path.
The whole `feature-cross-side-observability` feature is now DONE (Units 1–7 +
the relay half), and `feature-reconnect-reproduction`'s code-actionable items
are done. ~9 stories shipped + 2 spikes/verifications, all on `main`, working
tree clean, `flutter analyze` fully clean (the lingering `axisAlignment` lint
finally silenced), test suites green (app 662, pi-extension 752, relay 170).

### `feature-cross-side-observability` (COMPLETE)

| Unit | Story | Status |
|---|---|---|
| 1+2 | story-app-debug-log-adapter (typed DebugEvent registry + file adapter) | ✅ done (prior session) |
| 3 | story-app-debug-toggle-ui (Settings toggle + Export/Clear UI) | ✅ done |
| 4 | story-app-capture-routing (15 debugPrint sites + 6 ConnectionManager events incl. the conn-channel-lost {stale} takeover proof) | ✅ done (2 fix passes) |
| 5 | correlation key confirmation | ✅ verified |
| 6 | story-add-transport-frame-observability (peer-channel silent drops; collapsed after Unit 4 shipped the ws-in surface) | ✅ done |
| 7 | story-session-replacement-harness (SDK-seam harness: real ExtensionRunner + AgentSessionRuntime.newSession() + fake AgentSession shell; 5 tests, stale-ctx via real assertActive()) | ✅ done (spike + 1 fix pass) |
| relay | story-relay-duplicate-auth-supersession-log (authenticated {superseded_existing}; the relay half of the takeover proof) | ✅ done |

### `feature-reconnect-reproduction` (code-actionable items DONE)

| Item | Status |
|---|---|
| idea-extension-pumps-into-dead-app-peer → story-extension-suspend-fanout-on-peer-offline | ✅ done (CONFIRMED gap: relay emits peer_offline, extension didn't consume it; now consumes + suspends fan-out + drop-with-signal) |
| idea-mobile-user-message-not-delivered-timeout → verify + story-fix-resumed-session-echo-gate-rejection | ✅ done (RACE CONFIRMED by static trace: echo goes through SessionGate; after /resume a stale _activeRef rejects the echo → timer never disarms → "not delivered" badge. Fix: gate-tolerant echo disarm — the echo confirms delivery regardless of session id; transcript acceptance stays session-scoped) |
| idea-mobile-drop-half-open-tcp | ✅ answered (relay does NOT eagerly supersede — waits for ping timeout; behavior change deferred) |
| idea-mobile-drop-slow-recovery | ⏸️ live-repro-only (instrumentation in place) |
| idea-mobile-outgoing-message-swallowed | ⏸️ live-repro-only (correlation key in place) |

## The debug UX (what the operator sees on the phone)

Settings page has a new **Debug** section (after Relay/Display), with three controls:

1. **Debug logging** — a `SwitchListTile` (on/off). Subtitle: "Persist a
   bounded jsonl ring log for diagnosing mobile session bugs." Persisted in
   `Preferences.debugLogging` (default false). When OFF, `DebugLog.log()` is
   an early no-op (no serialization, no file I/O) — the callback wired in DI
   reads the pref live. When ON, capture flows across all peers/sessions into
   one ring until cleared or capped. **Toggling OFF preserves the existing
   ring/file** — only new capture is gated.

2. **Export debug log** — an `OutlinedButton` (share icon). Force-flushes,
   reads the file (source of truth), opens the **share sheet** via
   `share_plus` (`Share.shareXFiles` with `XFile.fromData`) as a file named
   `remote_pi_debug.jsonl` with ndjson MIME. Works **even while debug logging
   is OFF** (reads whatever is on disk). If empty: a "No debug log yet"
   snackbar. Otherwise: a "Debug log export opened" snackbar.

3. **Clear debug log** — an `OutlinedButton` (trash icon, red). Confirm dialog
   ("This wipes the saved debug ring file. The Debug logging switch stays
   unchanged."), then `clear()`. Wipes ring + file but **NOT** the toggle.
   Works while debug logging is OFF.

A privacy warning sits under the switch: "Exports may include truncated
message previews and diagnostic IDs. Share only with destinations you choose."

## Operator debug flow (answering the phone-state question)

Yes — to test the debug functionality you need to push a build to the phone
(sideload the APK). The flow:

1. Build on the VM: `cd app && flutter build apk --release` (mind the VM's
   3G Gradle heap + tmpfs-redirect notes in AGENTS.md), copy to workstation,
   `adb install -r` (per AGENTS.md sideload instructions).
2. On the phone: Settings → Debug → toggle **Debug logging** ON.
3. Reproduce the bug (e.g., wifi→cellular drop, a swallowed message, a
   "not delivered" badge).
4. Settings → Debug → **Export debug log** → share sheet. If the app is in a
   non-functional state with the agent session, the share sheet is independent
   of the session — it reads the file directly, so it works even if the chat
   is stuck/offline. **Send the jsonl to your workstation** (share to any app
   that can reach the workstation: email, a synced folder, a messaging app,
   etc.). The export is a plain file; any share destination handles it.
5. (Optional) Clear debug log after exporting to start fresh.

The export is machine-parseable jsonl (one event per line), matching the
extension's `audit.jsonl` shape so a single message id greps across all three
sides (app ring log ↔ extension audit.jsonl ↔ relay `env_id_tail`).

## What's captured + space requirements

**Capture surface** (when debug logging is ON):
- **ws-in** (8 sites in ws_transport.dart): inbound frame probes —
  preauth, envelope enqueue, dropped-malformed, missing-room, room-mismatch,
  control-accepted, control-malformed, malformed. Fields: bytes, kind, stage,
  senderRoom, controlType, error.
- **msg-send / msg-echo / msg-failed** (sync_service.dart): the send path.
  `msg-send` carries a truncated `_preview(text, image)` (NOT full text);
  blocked sends set `blocked:true` with no preview.
- **session-gate / session-sync**: gate rejections (session_mismatch /
  active_session_unknown / missing_session_id) + sync failures.
- **conn-status / conn-channel-lost / conn-hydrate / room-snapshot /
  working-conv** (connection_manager.dart): the reconnect state machine +
  the duplicate-connection-takeover proof (`conn-channel-lost {stale:true}`
  = replaced channel safely ignored; `stale:false` = current channel lost →
  retry). `working-conv` from both `markRoomWorking` and the ping-missed
  `_markActiveRoomOffline` path.
- **replay-dedup**: per-replay-event dedup tracking (incl. within-batch
  duplicates — the [I1] fix).
- **peerFrame** (peer_channel.dart): peer-channel silent drops
  (unsupported_type / malformed).

**Privacy**: no full message bodies, image data, tool args/results, or
signatures. Only peer tails (last 8 chars), room ids, byte counts, short
reasons, truncated previews, diagnostic IDs.

**Space**:
- **1 MiB cap** (`_defaultMaxBytes = 1 << 20`), single file
  `getApplicationDocumentsDirectory()/remote_pi_debug.jsonl`. Ring-truncate
  at cap (drop oldest lines), enforced on append (no overshoot between
  flushes). Per-field length caps (e.g. `_shortReason` ≤ 120 chars,
  `_eventIdTail` 12, `_peerTail`/`_sessionIdTail` 8) so a malformed untrusted
  string can't evict the window.
- The cap covers ~48h of the expanded capture surface per the adapter's
  estimate. With ~10-20 lines/turn incl. ConnectionManager transitions, 1
  MiB still covers the operator's "few hours to hit errors" window with
  headroom; monitor and tighten if a reconnect storm evicts too fast.
- **Crash-resilient flush**: critical events (send attempt, send failure/
  timeout, session-gate drop, status retry/offline/online, room snapshot/
  session rotation) flush immediately; routine events debounce 2s. The
  diagnostic tail is the whole point — losing it on a crash defeats the
  feature.
- The file is the source of truth: `export()` force-flushes then reads the
  file line-by-line (skipping unparseable lines), recovering disk state even
  if the in-memory ring diverged.

## The cross-side correlation key

The message id is shared across all three sides (confirmed by grep):
- app: `MsgSendEvent.id` / `MsgEchoEvent.id` (the `UserMessage.id`).
- extension: `pi-extension/src/index.ts:2016-2017` logs `app user_message id=${msg.id}`.
- relay: `relay/src/handlers/pi_forward.rs:201,219,228` derives/logs
  `env_id_tail` from `outbound.envelope.id`.

So one id greps across app ring log + extension audit.jsonl + relay file log.
`session_id` is a secondary correlation key.

## Review discipline (the throughline)

Every story went through implement → adversarial review (openai-codex/gpt-5.5,
fresh context) → fix → re-review until ACCEPTED → fast-lane advance. The catches:
- Unit 4 v2: within-batch-duplicate test lacked teeth (exercised the case the
  old logic handled, not the actual bug) — fixed with a test that FAILS under
  the old logic.
- Unit 4 bonus: two unreachable dead-branch emissions removed.
- Unit 6: `_shortReason` hardened to runtimeType-only (never e.toString()).
- Unit 7 [I1]: the onReplaced-rebind teeth gap — closed with a second-session_new test.
- Fan-out [I1]: fail-fast violation in presence decoding — fixed to reject the whole frame.
- Echo-gate: verify-before-fix — the static trace CONFIRMED the race rather than guessing.

## What's next

`epic-targeting-and-session-lifecycle-contracts` is now well-positioned:
- **`feature-contract-gap-audit`** — the downstream contract prose, now
  evidence-sourced from real observability rather than anecdotes (the original
  epic thesis, inverted: the contract follows from evidence).
- **A potential follow-up**: eager-close on duplicate auth (the behavior
  change the relay supersession story deferred, now that the observation is in
  place to validate it).
- The two live-repro-only items will attribute on the next drop test with the
  instrumentation now in place.

## Commit graph (this session)

```
2a53be8 review: story-fix-resumed-session-echo-gate-rejection → done
f0b2596 implement(app): story-fix-resumed-session-echo-gate-rejection — gate-tolerant echo disarm
8b07fb3 review: story-extension-suspend-fanout-on-peer-offline → done
7d2ec5f implement(pi-extension): story-extension-suspend-fanout-on-peer-offline
ab6e3dc verify: story-verify-resumed-session-echo-gate-rejection → done (RACE CONFIRMED)
c1be968 scope: feature-reconnect-reproduction — split code-actionable vs live-repro items
bbaa1ce scope: story-verify-resumed-session-echo-gate-rejection
ef11074 scope: story-extension-suspend-fanout-on-peer-offline
9422105 review: story-relay-duplicate-auth-supersession-log → done
25eaee7 implement(relay): story-relay-duplicate-auth-supersession-log
2d63c80 review: story-session-replacement-harness → done
1b58739 implement(pi-extension): story-session-replacement-harness
9038d49 session note: observability Units 3/4/6 done, Unit 7 in flight (prior)
d566f30 review: story-add-transport-frame-observability → done
f838058 implement(app): story-add-transport-frame-observability
4b8e0d4 spike(pi-extension): Unit 7 ExtensionRunner headless feasibility
2514b6c scope: story-add-transport-frame-observability collapsed
b428c5f review: story-app-debug-toggle-ui + story-app-capture-routing → done
b4c5a86 review: story-app-debug-toggle-ui + story-app-capture-routing (ACCEPTED)
d7bc84a implement(app): story-app-capture-routing
8a65bcc implement(app): story-app-debug-toggle-ui
0020dd3 (prior session note)
```
