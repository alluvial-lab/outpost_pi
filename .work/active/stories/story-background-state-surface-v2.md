---
id: story-background-state-surface-v2
kind: story
stage: review
tags: [app, ux]
parent: null
depends_on: []
release_binding: v0.11.1
gate_origin: null
created: 2026-08-30
updated: 2026-08-30
---

# Background-state surface v2: text bar + simplified dot + honest label

Operator UAT iteration on v0.11.1-rc.1 (2026-08-30): the pulsing-blue dot
is hard to distinguish from steady blue at tile scale; and "orchestrating"
over-specifies the signal (today subagents only; background bash/tests
should join via the same `background` field later — the label must
survive that broadening).

## Design (operator-confirmed 2026-08-30)

- **Tile dot**: simplify to blue for ANY work (steady — pulse removed),
  green idle, amber reconnecting, grey offline. The dot answers only
  "is something happening?".
- **Tile subtitle bar** (model/time line under the room name): while
  background is active (live-room gated), show `background work` in
  place of the model/time text; restore when it drains.
- **Chat chip**: `orchestrating…` → `background…` (same colors.working).
- **Wire field unchanged** (`background` — already the right name; zero
  protocol churn).
- In-chat header unchanged otherwise.

## Acceptance criteria

- Tile: dot steady blue for working OR background; subtitle swaps to
  `background work` only for background (not for turn-working); restores
  model/time on drain; not shown when room not live-gated.
- Chip label `background…` everywhere (widget tests updated from
  `orchestrating…`).
- Pulse animation removed with its controller/state fully cleaned up.
- `flutter analyze && flutter test --exclude-tags e2e` green from app/.

## Implementation notes

- Removed the tile presence-dot animation and kept background work steady blue.
- Added the live-gated `background work` subtitle swap with model/time restoration.
- Updated the chat status chip and widget coverage to use `background…`.
