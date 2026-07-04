---
id: story-app-capture-routing
kind: story
stage: implementing
tags: [app, observability]
parent: feature-cross-side-observability
depends_on:
  - story-app-debug-log-adapter
release_binding: null
gate_origin: null
created: 2026-07-04
updated: 2026-07-04
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

| Tag | File:line | Persisted fields |
|---|---|---|
| `conn-status` | `:520-553` (connect), `:1177-1184` (retry) | `status`, `attempt?`, `delayMs?`, `peerTail?`, `room?` |
| `conn-channel-lost` | `_onChannelLost` | `peerTail?`, `room?`, `reason` |
| `conn-hydrate` | `_replaySubscriptions:329-337,1136-1143` | `action`, `room?`, `snapshotCount?` |
| `room-snapshot` | `_onControl:566-706` | `room`, `presenceCount?`, `working?` |
| `working-conv` | `markRoomWorking:914-929`, `_markActiveRoomOffline:1194-1252` | `room`, `working`, `reason` |
| `replay-dedup` | `sync_service.dart` replay/backfill | `sessionId`, `eventIdTail`, `dropped` |

## Acceptance criteria

- [ ] All 15 existing sites route through `DebugLog.log`; logcat unchanged.
- [ ] `ConnectionManager` emits the 6 new event types at the transitions listed.
- [ ] No full message body / image data / tool args or results in any event.
- [ ] `msg-send` persisted line includes the truncated `preview`; NOT full text.
- [ ] Correlation: `id` in `msg-send`/`msg-echo` matches the extension's
  `app user_message id` and the relay's `env_id_tail` (one-line grep check).
- [ ] A fake-`DebugLog` test asserts the expected events fire on:
  - a reconnect path (status transitions, hydrate, room snapshot, working conv).
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
