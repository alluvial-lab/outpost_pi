---
id: story-mobile-transcript-reorder-after-backlog-flush
kind: story
stage: drafting
tags: [app, bug]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-27
updated: 2026-07-28
---

# Transcript reordered on phone after backlog flush + reconnects

## Observation (operator, 2026-07-27, live on the fixed 0.3.0+2 build)

Phone transcript displayed out of order. Expected order:
"what else is on the .work board?" (user) → board report (assistant) →
"let's groom" (user) → groom start (assistant). Actual display:
"let's groom" → the LATER assistant reply ("While the semantic pass runs…")
→ then the earlier "what else is on the .work board?" + board report — i.e.
a later assistant message sorted ABOVE the earlier user+assistant pair.

## Context (likely contributors)

Same day the channel carried: a ~450-frame offline backlog flush
(send_seq 66→514), multiple reconnects (5G/WiFi transitions), a pairing
with generation replacement, and the pairing-race fix build. Prime
suspects: backlog flush insertion position, replay/replay-dedup ordering,
timestamp skew vs arrival order in transcript projection.

## Direction

Reproduce with the captures in debug/ (938/94f series) + relay log
(2026-07-26/27): determine whether the jumbled rows are flushed-backlog
events inserted by arrival rather than canonical order, or a
projection/sort defect in the app's transcript ordering
(msgs_v3 + replay path). Check `sessionHistoryEventToTranscriptEvent`
identity/ordering and the live-append vs replay-merge path.

## Provenance
Promoted to standalone (parent: null) on 2026-07-28 when the parent epic
`epic-targeting-and-session-lifecycle-contracts` was retired. The epic's
observability thesis had self-executed (cross-side observability shipped,
3 of 5 cluster bugs resolved, 2 unreproduced with no recurrence in 3+ weeks),
so the epic arc was closed. This story is a fresh 2026-07-27 live observation
with a concrete repro direction and stays active.
