---
id: story-app-send-swallowed-session-identity-unavailable
kind: story
stage: drafting
tags: [app, bug]
parent: null
depends_on: []
release_binding: null
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
