---
id: story-orchestrating-room-tile-dot
kind: story
stage: implementing
tags: [app, ux]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-29
updated: 2026-08-29
---

# Room tile: pulsing-blue orchestrating dot (from parked UAT feedback)

From `backlog-orchestrating-room-tile-dot` (operator UAT feedback on
v0.11.0): the home-screen room tile shows plain green while the room's
agent orchestrates background work — indistinguishable from idle at a
glance.

## Design (operator direction 2026-08-29)

Orchestrating = *available-but-working*: the operator can send a turn
(composer stays enabled) while background work is in flight. Neither
steady green ("waiting on you") nor steady blue ("turn running") carries
that alone. Decision: **pulsing blue** — same `colors.working` hue as a
running turn, pulsing to mark self-driven background activity. No new
palette token, no theme-contract change (animation only).

## Work

- `app/lib/ui/home/widgets/session_tile.dart` — the 4-state dot
  (line ~116-133) becomes 5-state with precedence: `working` (steady
  blue) → `orchestrating` (pulsing blue, live-room gated background) →
  `reconnecting` (amber) → `live` (green) → offline (grey). Reuse an
  animation idiom already in the app (see
  `app/lib/ui/chat/widgets/streaming_bubble.dart` for the existing
  repeating-animation pattern); keep it subtle (opacity or gentle scale,
  no layout impact, respects the tile's 10px dot).
- Projection: thread `RoomInfo.background` from the home viewmodel
  through to the tile (gate on room-liveness exactly like the chat
  chip's `_backgroundProjection` in `chat_viewmodel.dart` — cached
  metadata is not trusted while disconnected).
- Chat chip unchanged (`orchestrating…` label already carries the
  distinction in-chat).

## Acceptance criteria

- Widget tests: tile dot renders steady blue for working, pulsing blue
  for background-only, green for idle, amber for reconnecting (background
  suppressed when not live-room gated); precedence working > background.
- `flutter analyze && flutter test --exclude-tags e2e` green from app/.
- Animation has no persistent timer leak (controller disposed; tile is
  currently StatelessWidget — converting the dot to a small StatefulWidget
  with proper dispose is acceptable).
