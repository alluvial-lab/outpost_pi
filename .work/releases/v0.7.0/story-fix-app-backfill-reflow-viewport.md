---
id: story-fix-app-backfill-reflow-viewport
kind: story
stage: done
tags: [app, ux, bug]
parent: null
depends_on: []
release_binding: v0.7.0
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

## Root cause
`_MessageList` was stateless and relied only on `ListView(reverse: true)`.
That keeps offset zero pinned to the newest row, but it does not preserve a
non-bottom reader's visible row and pixel offset when hydration inserts older
children at canonical positions. The sliver relayout therefore moved the
visible row even though stable message keys and database ordering were correct;
there was also no reconnect/hydration cue to distinguish the movement from
message reordering.

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

## Implementation notes
- **Execution capability:** Sol/high, selected for Flutter sliver geometry,
  lifecycle-owned controller/timer work, and viewport behavior under async
  hydration.
- **Files changed:** `app/lib/ui/chat/chat_page.dart`,
  `app/test/ui/chat/chat_page_appbar_test.dart`.
- **Regression test:** `backfill preserves a non-bottom viewport anchor and
  marks continuation` drives online -> retrying -> online -> delayed hydration.
  Fails-before evidence: the first visible row moved from y=157 to y=230 (73px)
  before the anchor implementation. It now verifies that older canonical
  backfill preserves the first visible row within 1px, bottom-pinned hydration
  stays at the newest row when a later turn arrives, and a four-second
  `Reconnected · transcript updated` affordance survives the realistic
  online-before-DB-update sequence.
- **Confirmation:** targeted chat suite passed (118 tests); `flutter analyze`
  reported no issues; full `flutter test --exclude-tags e2e --concurrency=2`
  passed (913 tests). Device viewport validation is deferred to the
  orchestrator soak.
- **Bounded inline review:** PASS. The stateful list owns and disposes its
  `ScrollController` and continuation timer, stable per-message keys remain
  bounded to the current transcript, restoration runs only after transcript
  changes, offset zero remains the bottom contract, and the affordance reuses
  existing theme tokens at the 12sp operational floor. No protocol, ordering,
  persistence, or ViewModel contract changed.
- **Adjacent issues parked:** none.
