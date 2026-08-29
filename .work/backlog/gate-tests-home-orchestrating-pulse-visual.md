---
id: gate-tests-home-orchestrating-pulse-visual
created: 2026-08-29
updated: 2026-08-29
tags: [testing, app]
release_binding: null
gate_origin: tests
---

# Exercise the orchestrating pulse through the production Home composition

## Priority
Medium

## Value evidence
Item: `story-orchestrating-room-tile-dot`

Contract / risk / regression / maintenance cost: the user-visible distinction
introduced by this story is specifically motion: background-only work must be a
*pulsing* working-blue dot rather than the steady working or idle colors. The
new widget coverage in `app/test/ui/home/session_tile_test.dart:40-101` proves
the color and the presence of a `FadeTransition`, but it never observes two
animation phases and never mounts the production `HomePage` projection from
room metadata through `HomeViewModel` into the tile. A controller that stopped,
never repeated, or remained at one opacity could therefore satisfy the current
assertions.

No visual/integration lane closes that gap. The existing extension → relay →
app background test ends at `RoomInfo.background`
(`app/test/e2e/background_room_meta_e2e_test.dart:24-140`). The fold Home fixture
renders its primary room as `working: true` and overrides it as working
(`app/test/golden/fold_matrix_fixtures.dart:66-80,177-199`), so its Home captures
exercise the steady-blue state, not background-only orchestration. The live
golden lane mounts Chat and does not inspect the Home tile
(`app/integration_test/live_golden_test.dart:20-78`). This is a material polish
confidence gain, but component tests already protect state precedence and
lifecycle disposal, so it is not release-blocking.

## Gap type
e2e-seam / visual state transition

## Suggested test
```dart
testWidgets('Home renders a repeating pulse for live background-only work', (tester) async {
  // Mount the production HomePage with a controllable ConnectionManager.
  // Announce one live room with background=true and working=false.
  // Assert the Home tile is working-blue, then sample FadeTransition.opacity
  // at two deterministic controller phases and require a meaningful change.
  // Advance through a full cycle to prove repetition, then publish working=true
  // and assert the dot becomes steady without changing hue.
});
```

Prefer deterministic pumps and direct animation values over wall-clock sleeps.
If the fold render-evidence matrix is extended, add a background-only Home
fixture and capture a named deterministic pulse phase rather than relying on an
arbitrary settle instant.

## Test location (suggested)
`app/test/ui/home/home_page_orchestrating_test.dart` (or a focused extension of
`app/test/ui/home/session_tile_test.dart` plus the fold Home fixture)
