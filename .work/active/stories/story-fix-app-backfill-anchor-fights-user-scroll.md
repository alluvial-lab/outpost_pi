---
id: story-fix-app-backfill-anchor-fights-user-scroll
kind: story
stage: implementing
tags: [app, bug]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-23
updated: 2026-08-23
---

# Backfill viewport anchoring restores stale anchors and fights user scroll

## Symptom
Deferred verification soak (0.6.2+10, seed 20260828, PINless AVD — lane itself
verified healthy) failed the rendered-bubble oracle:
`_assertEveryMaintainedBubbleRenders` → `dragUntilVisible` → "Bad state: No
element" after maxScrolls — a maintained transcript id unreachable by scroll
while faults keep inserting rows. Evidence:
`.work/session-notes/live-soak-20260823T230319Z-20260828/` (frame #6 =
generated line 447 = e2e/live_soak.py `_assertEveryMaintainedBubbleRenders`).

## Root cause (to confirm)
`chat_page.dart` c7503f62 anchoring: `_captureAnchor()` on transcript change
+ post-frame `_restoreAnchor()`. During continuous backfill (fault windows),
every insert captures the CURRENT first-visible, then restore logic applies a
STALE anchor (captured before subsequent scrolls), repeatedly overriding the
viewport — user/programmatic upward scroll never accumulates; older bubbles
are unreachable while inserts continue. Passed 0.5.2 (no anchoring); regressed
0.6.2.

## Fix approach
Anchor semantics per the original story: (a) at-bottom → stay pinned to
newest; (b) scrolled up → the USER's current first-visible row stays stable
across inserts (anchor refreshes to follow the user, never overrides them);
(c) only a genuine hydration REBUILD (cold projection rebuild) may re-place
the viewport, once. No post-frame restore that retroactively moves a
viewport the user has since scrolled.

## Regression test
Widget test (fails-before): transcript streaming inserts while the test
scrolls up N times → assert cumulative scroll offset is preserved (first-
visible row id unchanged across the next insert) and an older-than-anchor
bubble is reachable by scroll during continued inserts.

## Verification
300s live soak green (seeds 20260828 + one fresh) with the rendered-bubble
oracle active — that oracle IS the contract here.
