---
id: story-app-capture-routing
kind: story
stage: done
review_addressed: 2026-07-05
tags: [app, observability]
parent: feature-cross-side-observability
depends_on:
  - story-app-debug-log-adapter
release_binding: null
gate_origin: null
created: 2026-07-04
updated: 2026-07-05
---

# App debug log: emit diagnostic events at the expanded capture surface

## Scope (Unit 4 of `feature-cross-side-observability`)

The actual gap closure — what makes the ring log diagnose the reconnect
cluster, not just repackage existing breadcrumbs. Two parts:

### 4a — Route the existing 15 `debugPrint` sites
**Files**: `app/lib/data/transport/ws_transport.dart`, `app/lib/data/sync/sync_service.dart`

Route through `DebugLog.log(event)`, keeping the existing `debugPrint` as the
verbose logcat path. `DebugLog` is persistence-only (does NOT mirror to
logcat — review B3). Corrected tags (review B1):

| Tag | File:line | Persisted fields | Scrub |
|---|---|---|---|
| `ws-in` | `ws_transport.dart:82,103,106,113,117,127,133,142` | `bytes`, `kind`, `stage`/`senderRoom`/`controlType`/`error` | field-length caps |
| `msg-send` | `sync_service.dart:212,245,260` | `id`, `blocked`/state, `preview` (:260 only) | full body scrubbed; preview = truncated `_preview` |
| `msg-echo` | `sync_service.dart:610` | `id` | — |
| `msg-failed` | `sync_service.dart:341` | `id`, `code`, `detail` | detail = short reason |
| `session-gate` | `sync_service.dart:538` | `messageType`, `reason`, `sessionIdTail` | — |
| `session-sync` | `sync_service.dart:425` | `err` | err = short reason |

### 4b — ADD first-class events at `ConnectionManager` (the A1 gap)
**File**: `app/lib/data/transport/connection_manager.dart`

Line numbers verified against `connection_manager.dart` (review v2 #4):

| Tag | File:line | Persisted fields |
|---|---|---|
| `conn-status` | `:534` (`StatusConnecting`), `:547` (`StatusOnline`), `:1183` (`StatusRetrying` in `_scheduleRetry:1177`) | `status`, `attempt?`, `delayMs?`, `peerTail?`, `room?` (no `StatusOffline` emitted today — leave it out until/unless added) |
| `conn-channel-lost` | `_onChannelLost:1162-1175`, BOTH branches | `peerTail?`, `room?`, `stale` (stale=true at `:1167` = replaced channel's onDone safely ignored; stale=false at `:1173` = current channel lost → retry started) |
| `conn-hydrate` | `_replaySubscriptions:1136-1143` (from `requestResumeHydration:329-337`) | `action`, `room?`, `snapshotCount?` |
| `room-snapshot` | `_onControl:566`, `RoomAnnounced` case `:612`, `RoomMetaUpdated` case `:697`, `RoomsSnapshot` case `:743` | `room`, `presenceCount?`, `working?` |
| `working-conv` | `markRoomWorking:914` (guards `:921`, mutation `:938`), `_markActiveRoomOffline:1238` (from `_startPing:1218`) | `room`, `working`, `reason` |
| `replay-dedup` | `sync_service.dart` replay/backfill | `sessionId`, `eventIdTail`, `dropped` |

**The `conn-channel-lost {stale}` event is the duplicate-connection-takeover
proof** for the app side — it distinguishes "old replaced channel closed,
safely ignored" from "current channel lost, retry started" (the
self-sustaining-retry-loop footgun the code comment at `:1166-1170` warns
about). The relay-side half ("did the relay supersede the old conn immediately
on duplicate auth, or after ping timeout?") lands as a separate follow-up:
`story-relay-duplicate-auth-supersession-log`.

## Acceptance criteria

- [ ] All 15 existing sites route through `DebugLog.log`; logcat unchanged.
- [ ] `ConnectionManager` emits the 6 new event types at the transitions listed.
- [ ] `conn-channel-lost` fires on BOTH branches of `_onChannelLost:1162-1175`
      with `stale=true` (replaced channel ignored) and `stale=false` (current
      channel lost → retry) — the takeover proof.
- [ ] No full message body / image data / tool args or results in any event.
- [ ] `msg-send` persisted line includes the truncated `preview`; NOT full text.
- [ ] Correlation: `id` in `msg-send`/`msg-echo` matches the extension's
  `app user_message id` and the relay's `env_id_tail` (one-line grep check).
- [ ] A fake-`DebugLog` test asserts the expected events fire on:
  - a reconnect path (status transitions, hydrate, room snapshot, working conv).
  - a duplicate-connection takeover (stale `conn-channel-lost` ignored, then
    fresh `conn-status` online — no spurious retry).
  - a real channel loss (current `conn-channel-lost` → `conn-status` retrying).
  - a send path (`msg-send` with truncated preview, `msg-echo`).
  - a session-gate drop (`session-gate` with reason).
  - a `msg-failed` and `session-sync` failure.
- [ ] A static/registry test fails if a declared `DebugEvent` variant has no
  routing test (catches a silently-stopped emitter — review E2).
- [ ] `flutter analyze` clean; `flutter test` green.

## Out of scope

- The adapter (story-app-debug-log-adapter).
- The toggle UI (story-app-debug-toggle-ui) — but this story's routing is
  inert when the toggle is OFF (the adapter early-returns).

## References

- Parent: `feature-cross-side-observability.md` (Unit 4, the A1 expansion).
- Review: `.work/reviews/review-feature-cross-side-observability-design-2026-07-04.md`
  (A1 ConnectionManager gap, B1 mislabeled tags, B3 persistence-only, E2 routing tests).
- `app/lib/data/transport/connection_manager.dart` — the reconnect state machine.
- `app/lib/data/transport/ws_transport.dart`, `app/lib/data/sync/sync_service.dart` — the 15 sites.

## Implementation notes

- Per-file changes:
  - `app/lib/data/transport/ws_transport.dart`: added optional constructor/static-connect `DebugLog` injection and emitted `WsInEvent` beside each existing `[ws-in]` `debugPrint`; logcat text is unchanged.
  - `app/lib/data/sync/sync_service.dart`: added optional `DebugLog` injection and emitted `MsgSendEvent`, `MsgEchoEvent`, `MsgFailedEvent`, `SessionGateEvent`, `SessionSyncEvent`, and `ReplayDedupEvent`; `msg-send` persists `_preview(text, image)` only.
  - `app/lib/data/transport/connection_manager.dart`: added optional `DebugLog` injection and emitted `ConnStatusEvent`, `ConnChannelLostEvent`, `ConnHydrateEvent`, `RoomSnapshotEvent`, and `WorkingConvEvent`; `conn-channel-lost.stale` follows the existing `!identical(cur, ch)` stale-channel branch exactly.
  - `app/lib/config/dependencies.dart`: production constructors now receive `_injector.get<DebugLog>()`; the `DebugLogImpl` registration from the parallel toggle-UI slice was present and reused.
  - `app/test/data/debug/debug_capture_routing_test.dart`: added fake-`DebugLog` routing coverage for ws inbound, reconnect/hydrate/room/working transitions, stale vs current channel loss, send/echo/gate/failure/sync/replay-dedup, blocked send, and registry tag coverage.
- Line-number drift found before edits:
  - `ws_transport.dart`: design `:106` is current `:107` for the envelope `ct.bytes` debugPrint after formatting/nearby comments; all other listed `[ws-in]` sites matched by surrounding context (`:82`, `:103`, `:113`, `:117-118`, `:127-128`, `:133-134`, `:142-143`).
  - `sync_service.dart`: listed sites matched by surrounding context (`:212`, `:245-246`, `:260`, `:341-342`, `:425`, `:538-542`, `:610`).
  - `connection_manager.dart`: listed sites matched before edits (`StatusConnecting :534`, `StatusOnline :547`, `_onControl :566`, `RoomAnnounced :612`, `RoomMetaUpdated :697`, `RoomsSnapshot :743`, `markRoomWorking :914`, `_replaySubscriptions :1136`, `_onChannelLost :1162`, `StatusRetrying :1183`, `_markActiveRoomOffline :1238`). `adopt()` also emits `StatusOnline` and now logs the same `conn-status` shape.
- Tests added:
  - `WsTransport routes inbound frame probes through DebugLog` uses a local WebSocket relay and real `WsTransport.connect` with fake `DebugLog`.
  - `ConnectionManager emits reconnect, hydrate, room snapshot, and working convergence events` uses real `ConnectionManager` with fake storage/channel.
  - `ConnectionManager distinguishes stale takeover close from real channel loss` asserts stale `conn-channel-lost` does not retry, while current-channel loss does emit retrying.
  - `SyncService emits send preview, echo, gate, failure, session-sync, and replay-dedup events` asserts exact variants/fields and preview truncation.
  - `SyncService emits offline held-pending msg-send when channel is unavailable` covers the offline held-pending send path.
  - `SyncService emits blocked msg-send when session identity is unavailable` covers the missing-session blocked send path.
  - `every DebugTag has an asserted routing test in this suite` enumerates `DebugTag.values` and requires each tag to have been recorded by a real `_assertEvent` emission assertion.
- Verification output:
  - `flutter test test/data/debug/debug_capture_routing_test.dart` → `All tests passed!` (`00:00 +7`).
  - `flutter test` → `All tests passed!` (`00:33 +656`).
  - `flutter analyze` → exit 1 with the pre-existing unrelated info noted in `app/CLAUDE.md`: `lib/ui/chat/widgets/input_bar.dart:802:7 deprecated_member_use ('axisAlignment' is deprecated...)`; no new analyzer errors were reported.
- Correlation-key grep result: `app/lib/data/sync/sync_service.dart` persists the same `UserMessage.id` in `MsgSendEvent`/`MsgEchoEvent`; `pi-extension/src/index.ts:2016-2017` logs `app user_message id=${msg.id}`; `relay/src/handlers/pi_forward.rs:201,219,228` derives/logs `env_id_tail` from `outbound.envelope.id`.
- Deviations / notes:
  - `RoomSnapshotEvent` requires `room`, so no event was emitted at the generic `_onControl` function entry; events are emitted in the room-bearing `RoomAnnounced`, `RoomMetaUpdated`, and `RoomsSnapshot` branches.
  - `MsgSendEvent` has `blocked` but no free-form state field; both blocked send sites set `blocked: true` and the real send sets `blocked: false` with the truncated preview.
  - A small `@visibleForTesting debugSimulateChannelLost` seam was added to exercise the otherwise race-dependent stale/current `_onChannelLost` branches without mocking the branch logic.

## Review fixes (adversarial review, 2 passes)

Pass 1 found two important issues; both fixed:

- **[I1] `ReplayDedupEvent.dropped` false-negative for within-batch duplicates**
  (`sync_service.dart` replay-dedup block). The original `dropped` derivation
  checked only against IDs that pre-existed in the store before `appendAll`.
  A `SessionHistory` containing the same `eventId` twice would log
  `dropped:false` for BOTH occurrences (since neither pre-existed), even
  though `appendAll` skips the second — a false-negative exactly in the
  collision case the ring log exists to diagnose. Fixed with a mutable
  `seenEventIds` set seeded from the pre-read, then
  `final dropped = !seenEventIds.add(event.eventId);` per replay event, so
  the second within-batch duplicate correctly reports `dropped:true`.
  Regression test added: `SyncService replay-dedup reports within-batch
  duplicate eventIds as dropped` — constructs a `SessionHistory` with the
  SAME `id` AND SAME `ts` (so `serverReplayEventId` produces one eventId
  for both), asserts first `dropped:false`, second `dropped:true`. This
  test FAILS under the old logic (both would be `dropped:false`).

- **[I2] registry test was tag-exhaustive but not capture-site-exhaustive**
  (`debug_capture_routing_test.dart`). The original registry only checked
  each `DebugTag` had one assertion; deleting specific branch emissions
  (ws-in missing-room/room-mismatch/control/malformed, RoomMetaUpdated,
  RoomsSnapshot, _markActiveRoomOffline) would still pass. Replaced with a
  site-coverage registry: a `requiredSites` list of
  `(tag, siteName, discriminant)` tuples, where the check filters by tag
  AND discriminant (so a vacuous discriminant can only match events of
  the correct tag). Added real coverage for the previously-uncovered
  branches: a dedicated `WsTransport routes every ws-in dropped/control
  branch through DebugLog` test (drives real `WsTransport.connect` against
  a local relay pushing crafted frames for each `WsInboundFrameKind`),
  and a `ConnectionManager marks the active room offline after 3 missed
  pings` test (uses `FakeAsync` + an injected short `pingInterval` to
  advance 3 ping cycles and assert the `WorkingConvEvent` with
  `reason == 'ping_missed_room_offline'`).

- **Bonus finding (dead-branch removal)**: the implementer had added
  `WsInEvent` emissions to two UNREACHABLE branches in `ws_transport.dart`:
  the `envelopeBytes == null` branch under `WsInboundFrameKind.enqueue`
  (unreachable: `demuxPostAuthInboundFrame` only returns `enqueue` after a
  successful `_b64Decode`, so `envelopeBytes` is always non-null), and the
  `control == null` branch under `WsInboundFrameKind.control` (unreachable:
  the demux only returns `control` when `ControlInbound.tryFromJson`
  returned non-null). Removed both dead branches, replaced with `!`
  non-null assertions + invariant comments. The reachable `dropMalformed`
  path (which catches all decode failures via `try/on Object catch`) is
  intact.

- **Testability improvement**: `ConnectionManager` gained a real
  `pingInterval` constructor param (default `const Duration(seconds: 25)`,
  not a `@visibleForTesting` seam) so the missed-ping →
  `_markActiveRoomOffline` path is exercisable in `FakeAsync` without
  real-time waits.

Pass 2 (final) confirmed [I1] test has teeth (fails under old logic) and
[I2] registry is sound (tag-filtered, non-vacuous discriminants). The
`RoomAnnounced`/`RoomMetaUpdated` branches emit the same `RoomSnapshotEvent`
shape, so the registry collapses them into one `room-announced-or-meta-updated`
site; the per-phase reconnect test (with `events.clear()` between phases) is
the real proof both branches fire independently.

Final verification (combined tree):
- `flutter test` → `All tests passed!` (`+659`; +19 over the 640 baseline).
- `flutter analyze` → clean except the pre-existing `axisAlignment`
  deprecation in `input_bar.dart:802` (untouched, documented in `app/CLAUDE.md`).
