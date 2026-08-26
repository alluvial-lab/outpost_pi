---
id: app-hydration-truncated-flag-not-surfaced
kind: story
stage: drafting
tags: [app, ux]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-25
updated: 2026-08-26
---

# Session hydration truncation is invisible in the app

Observed during v0.3.0 UAT (2026-07-25): after a fresh pairing, the first
visible transcript message was mid-session — correct behavior (hydration is
bounded to `SYNC_LIMIT_DEFAULT = 30` transcript events, extension-side
`syncLimit()`, tunable via `OUTPOST_PI_SYNC_LIMIT`) — but the operator read
it as a possible bug because nothing indicates earlier history exists.

The wire already carries the signal: `session_history.truncated` is parsed
(`app/lib/protocol/generated/protocol.g.dart:1138`) but never consumed in
`app/lib/data/sync/` or `app/lib/ui/`.

Direction: surface a subtle "earlier history on this device is not synced"
affordance at the top of the transcript when `truncated` is true (and/or let
the app request a larger limit in `session_sync` for on-demand backfill).
Not release-blocking; the bounded sync is the designed contract.
