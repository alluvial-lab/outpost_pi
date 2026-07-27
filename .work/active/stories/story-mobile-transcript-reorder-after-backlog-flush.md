---
id: story-mobile-transcript-reorder-after-backlog-flush
kind: story
stage: drafting
tags: [app, bug]
parent: epic-targeting-and-session-lifecycle-contracts
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-27
updated: 2026-07-27
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
