---
id: story-fix-app-backfill-anchor-fights-user-scroll
kind: story
stage: done
tags: [app, bug]
parent: null
depends_on: []
release_binding: v0.7.0
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

## Root cause
`chat_page.dart` 8df47e90 stored each row's geometry key as the list child's
only key, replacing the prior `ValueKey(message.id)` contract. The soak oracle
therefore could not locate even the baseline `sync_0` bubble: its captured log
contains one DB/projection id and fails immediately in `dragUntilVisible` with
`Bad state: No element`, before continuous fault insertion begins. Separately,
the new post-frame restore used shared mutable anchor state with no revision or
user-scroll invalidation, so a queued restore could still apply after a newer
transcript update or user movement.

## Fix approach
Keep the public/stable `ValueKey(message.id)` on each list child and nest the
private `GlobalKey` used for render geometry beneath it. Make every captured
anchor an immutable restore request with a monotonic revision; only the newest
request may restore, and any `UserScrollNotification` invalidates it. Bottom
readers remain pinned, while a scrolled-up reader's newly captured first-visible
row follows their movement across later inserts instead of an obsolete request
moving them back.

## Regression test
`app/test/ui/chat/chat_page_appbar_test.dart` extends the original backfill
widget test with five scroll-plus-insert cycles. It asserts that the user's
scroll offset accumulates, then uses the production oracle's
`ValueKey<String>(message.id)` lookup to reach an older-than-anchor bubble while
inserts continue. Fails-before evidence: `scrollUntilVisible` threw the same
`Bad state: No element` stack as the device soak; the preceding cumulative-
offset assertion passed, disproving that the captured soak failed because
inserts had already frozen scrolling.

## Verification
300s live soak green (seeds 20260828 + one fresh) with the rendered-bubble
oracle active — that oracle IS the contract here.

## Implementation notes
- **Execution capability:** Sol/high, selected for Flutter scroll geometry,
  post-frame lifecycle ordering, and live-device regression verification.
- **Files changed:** `app/lib/ui/chat/chat_page.dart` and
  `app/test/ui/chat/chat_page_appbar_test.dart`.
- **Four-step confirmation:** the extended widget test reproduced the device
  exception before the fix and passes after it; the complete original chat-page
  test file passes (2 tests); `flutter test --exclude-tags e2e --concurrency=2`
  passes all 913 tests; `flutter analyze` reports no issues. The two required
  device soaks are recorded by the worker after the harness hardening commit.
- **Bounded inline review:** PASS. Stable list identity remains the message id;
  the geometry `GlobalKey` remains unique and bounded by transcript pruning;
  restore requests are immutable and revision-gated; real user scrolling
  invalidates queued restores; bottom pinning and reconnect continuation timing
  retain their original behavior. No ViewModel, persistence, protocol, or
  ordering contract changed.
- **Adjacent issues parked:** none.
