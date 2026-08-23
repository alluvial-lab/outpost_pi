---
id: story-fix-app-backfill-reflow-viewport
kind: story
stage: implementing
tags: [app, ux, bug]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-23
updated: 2026-08-23
---

# Interrupted-turn backfill on reconnect reflows the visible transcript (perceived reordering)

## Symptom
Operator report 2026-08-23 ("text/turn reordering"): a turn interrupted by
a network drop back-fills from replay on reconnect; older-turn content
inserts after newer visible content (canonical DB order is correct —
ordering oracle passes; the VISIBLE list jumps). No duplication (replay
dedup clean) — this is presentation.

## Root cause (to confirm)
On hydration after reconnect, back-filled rows insert at canonical
positions while the ListView viewport follows insertion rather than the
user's anchor; combined with an interrupted turn resuming mid-list, the
perceived order shuffles.

## Fix approach
Viewport pinning on back-fill: preserve the user's scroll anchor across
hydration inserts (keep the newest VISIBLE row pinned when the user is at
bottom; otherwise keep the current first-visible row stable with offset),
plus an interrupted-turn affordance (e.g. the resumed turn marked
"reconnected" where it resumes) so the reflow reads as continuation, not
reordering. Explore simply; the anchor-preservation is the core.

## Regression test
Widget test: transcript with turn A partial visible at bottom ->
hydration inserts A's remainder + a later turn B -> assert the viewport
remains anchored (bottom stays bottom / first-visible stays stable) and no
visible jump. Fails-before.

## Verification notes
Depends on A (fewer interruptions) but stands alone for the UX contract.
