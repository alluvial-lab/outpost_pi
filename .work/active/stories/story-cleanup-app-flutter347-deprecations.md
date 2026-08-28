---
id: story-cleanup-app-flutter347-deprecations
kind: story
stage: review
tags: [app, cleanup]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-28
updated: 2026-08-28
---

# App Flutter 3.47 deprecation cleanup

From the 2028-08-28 version-delta code sweep — candidate 6 in
`.work/backlog/backlog-post-stack-v010-code-cleanup.md`. Candidate 7
(`Future.pause`) stays parked (floor-bound to the next
`sdk:` floor-touching change — do NOT bump the pubspec floor here).

## Work

- `app/lib/ui/chat/widgets/input_bar.dart:824-830`: replace the
  deprecated `SizeTransition.axisAlignment: -1.0` + its analyzer-ignore
  + stale pin-era comment with `alignment: const Alignment(-1.0, -1.0)`
  (migration documented in the installed
  `packages/flutter/lib/src/widgets/transitions.dart:498-509`). Verify
  the rendered behavior is identical (same axis alignment semantics).

## Acceptance evidence

- `flutter analyze && flutter test --exclude-tags e2e` green from app/.
- No ignore_for_file additions; the comment removal leaves no stale
  pin-reference prose behind.

## Implementation notes

- Replaced `SizeTransition.axisAlignment: -1.0` and its local analyzer ignore
  with `alignment: const Alignment(-1.0, -1.0)` in
  `app/lib/ui/chat/widgets/input_bar.dart`; removed the stale Flutter pin
  comment.
- Verified against the installed Flutter SDK migration guidance in
  `packages/flutter/lib/src/widgets/transitions.dart:498-509`: for a
  horizontal transition, `axisAlignment` maps to the alignment x-coordinate,
  so `-1.0` remains start-aligned with the explicit alignment.
- Verification passed from `app/`: `flutter analyze && flutter test
  --exclude-tags e2e` (all 1001 tests passed).
