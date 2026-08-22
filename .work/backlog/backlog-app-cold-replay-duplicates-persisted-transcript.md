---
id: backlog-app-cold-replay-duplicates-persisted-transcript
created: 2026-08-22
updated: 2026-08-22
tags: [app, bug]
---

Promoted to `story-fix-app-cold-replay-duplicates-persisted-transcript`.

# Cold reconnect replay duplicates transcript rows already persisted in Hive

The deterministic grid reproduced duplicate bubbles after an app force-stop
and preserving Pi restart. In-process reconnects correctly dropped replayed
event ids, but the fresh app process had lost the in-memory seen-event set.
Cold `session_sync` accepted events whose transcript rows already existed in
Hive and appended them again, so the baseline user prompt rendered twice.

Evidence is in the local bundle
`.work/session-notes/live-grid-20260822-green2/`: `report.md`,
`outpost_pi_debug-20260822T182421Z.jsonl`, `triage.txt`, and the Flutter logs.
After cold hydration rendered `messageCount=7`, replay accepted persisted
`eventIdTail` values `787422973229`, `787422996687`, and `787423001432`; the
exact-one baseline assertion then found two matching bubbles.

## Work

Make replay admission durable across app processes. Hydrate the dedupe index
from the canonical persisted transcript-event store, or enforce idempotence at
the Hive write boundary using the stable `(sessionId, eventId)` identity. Keep
the `cold_open/pi_restart` grid assertion exact and flip its linked skip when
fixed.
