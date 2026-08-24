---
id: story-app-send-swallowed-session-identity-unavailable
kind: story
stage: done
tags: [app, bug]
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: null
created: 2026-08-21
updated: 2026-08-21
---

# sendMessage silently drops the message when session identity is unavailable

**Confirmed from operator debug capture `debug/cad-11f1-b349-a5efddf14d8d.bin`**
(4-day NDJSON ring, 8317 events, span 2026-08-16→08-20).

## Evidence

- 15:38:09 channel lost → retry → **15:38:15 online + connHydrate**.
- **15:39:18 `msgSend` id=`cli_01a01fd3-a3a7-760a-9c9e-ecf9676240fd`
  `blocked:true`** — 63s after reconnect, connection online, envelopes
  flowing in — and **no msgEcho ever** (the four earlier sends each echoed
  twice within ~0.5s). Log ends 15:39:35.
- Code: `app/lib/data/sync/sync_service.dart:355-362` — when
  `ref == null || sessionId == null/empty` the send logs
  `blocked: session identity unavailable` and **returns before the
  optimistic pending row** (`:375+`). No row, no timeout, no retry, no
  user-visible error. Contrast the *held* branch (`:405-416`): pending row,
  20s visible timeout, reconnect re-send.

## Two defects, one story

1. **Root cause:** reconnect hydration restored room/connection state but
   not `_activeRef`/sessionId for 63+s (possibly indefinitely until
   re-navigation) — investigate the hydrate→sessionRef restore path
   (`connHydrate` event fires; active session ref is not rebuilt).
2. **Contract break (fix regardless of #1):** `sendMessage` must never
   silently discard user input. Identity-unavailable should queue/surface
   like the held path (pending row + visible failure + re-send when
   identity restores), not vanish.

## Verification

Regression test derived from the capture sequence: reconnect → hydrate →
send before session ref restores → assert the message is either delivered
or visibly pending/failed — never absent. Chaos-harness scenario once
`feature-e2e-live-oddities-suite` exists.

## Root cause

`ConnectionManager` persisted room/cwd metadata but omitted the room's
canonical `session_id`. `_restoreCachedRooms()` therefore reconstructed a room
that could reconnect and receive envelopes while `activeSessionId` remained
null until a later room frame happened to carry identity. `SyncService`
correctly refused to send without a canonical `RemoteSessionRef`, but its
blocked branch returned before creating any optimistic projection, timeout, or
retry state, turning that safety check into silent data loss.

## Fix approach

Persist and restore the optional room `session_id` so cold/reconnect hydration
can rebuild `_activeRef` immediately. Independently retain identity-blocked
submissions as visible in-memory pending rows, mark them visibly failed after
the normal pending timeout, migrate them into the canonical transcript when
identity arrives, and re-send them through the existing held-message path with
the original client id.

## Regression test

- `app/test/data/transport/connection_manager_test.dart` restores a cached room
  before relay hydration and requires `activeSessionId` to be available.
- `app/test/ui/chat/chat_viewmodel_test.dart` reproduces online room hydration
  without identity, sends immediately, requires pending then failed visibility,
  restores identity, and requires re-send plus echo confirmation without a
  duplicate row.

## Failing reproduction

Before the fix:

```text
ConnectionManager reconnect hydration restores the cached canonical session identity before relay hydrate
Expected: 'cached-session'
Actual: <null>

reconnect hydrate send before session identity is visible then re-sent
Expected: an object with length of <1>
Actual: WhereTypeIterable<UserMsg>:[]
the send must never be absent
```

Command: `flutter test test/data/transport/connection_manager_test.dart test/ui/chat/chat_viewmodel_test.dart --concurrency=2` (34 passed, 2 failed).

## Implementation notes

- **Execution capability:** `sol/high`, selected because the fix spans persisted
  reconnect identity, transcript migration, UI projection, and lifecycle timers,
  while remaining one focused app-side repair.
- **Files changed:** `app/lib/pairing/storage.dart`,
  `app/lib/data/transport/connection_manager.dart`,
  `app/lib/data/sync/sync_service.dart`,
  `app/lib/ui/chat/viewmodels/chat_viewmodel.dart`, regression/live tests, and
  the nightly expected-findings inventory/oracle.
- **New regression evidence:** the two tests in the Regression test section now
  pass. The nightly oracle now treats a `sendQueue` held/visible-fail event as
  proof that a blocked submission was surfaced rather than swallowed.
- **Four-step confirmation:** targeted regression tests passed; `flutter
  analyze` reported no issues; `flutter test --exclude-tags e2e
  --concurrency=2` passed all 884 tests; `e2e/run-live.sh
  integration_test/live_failure_test.dart` passed the reconnect immediate-send
  scenario and the remaining enabled failure-lane scenarios with no swallow.
- **Test integrity:** a pre-existing 40 ms timer assertion flaked under the full
  two-worker suite, so its real-time window was widened while still waiting
  beyond the configured deadline; the full suite then passed.
- **Nightly manifest:** removed only
  `story-app-send-swallowed-session-identity-unavailable`; all other known-open
  findings remain.
- **Adjacent issues:** `app-hydration-truncated-flag-not-surfaced` remains
  parked and unchanged.

## Bounded inline review

**Verdict: PASS.** Reviewed the committed diff against the capture sequence,
session-scoped persistence contract, lifecycle teardown rules, and regression
assertions. Cached identity is backward-compatible and optional; identity-held
rows are filtered to the active room, deduplicated against durable rows, fenced
by lifecycle generation during migration, and their timers close on bind or
dispose. Re-send preserves the original id and steering semantics. No material
blockers or unrelated production changes remain. Per standalone-story policy,
this was an inline self-review with no independent or cross-model reviewer.
