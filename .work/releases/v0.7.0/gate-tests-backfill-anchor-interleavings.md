---
id: gate-tests-backfill-anchor-interleavings
kind: story
stage: done
tags: [testing, app]
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: tests
created: 2026-08-24
updated: 2026-08-25
---

# Exercise viewport-anchor revision fences before the queued restore runs

## Priority
High

## Value evidence
Item: `story-fix-app-backfill-anchor-fights-user-scroll`. The root-cause claim
has two parts: restore stable `ValueKey(message.id)` lookup and prevent an old
post-frame anchor restore from fighting newer inserts or user movement. Its
fails-before evidence proves only the missing public key (`Bad state: No
element`); the cumulative-scroll assertion already passed before the fix. The
current five-cycle test fully pumps each drag before each insert and fully pumps
each insert before the next cycle
(`app/test/ui/chat/chat_page_appbar_test.dart:203-209`), so it never interleaves
a user gesture or a second transcript update with the queued
`addPostFrameCallback` restore at `app/lib/ui/chat/chat_page.dart:710-714`.

## Gap type
bug-regression / explicit async interleaving

## Suggested test
```dart
// Hold the frame boundary explicitly.
// A. Emit backfill update A (queues restore), perform a real user drag before
//    A's post-frame callback, then pump: the user's resulting offset wins.
// B. Emit updates A and B before one frame: only B's captured anchor may apply.
// Assert the first-visible message and pixel offset, not implementation fields.
// Demonstrate fails-before against the pre-revision/pre-scroll-invalidation
// implementation so the second root-cause claim has independent evidence.
```

## Test location (suggested)
`app/test/ui/chat/chat_page_appbar_test.dart`

## Implementation
Extended the real chat viewport regression with a frame-held insert followed
by a user drag, two transcript inserts before one frame, and exact
`maxScrollExtent`/`minScrollExtent` boundary cases. Assertions stay on public
pixel offsets and stable keyed message positions.

Evidence: **pins-contract** — the revision and user-scroll fences already
preserve the observable anchor; the new interleavings now exercise those
contracts directly.
