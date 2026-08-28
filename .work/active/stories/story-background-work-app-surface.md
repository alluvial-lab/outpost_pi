---
id: story-background-work-app-surface
kind: story
stage: done
tags: [app, ux]
parent: feature-background-work-working-state
depends_on: [story-background-work-ext-tracker]
release_binding: null
gate_origin: null
created: 2026-08-27
updated: 2026-08-27
---

# App surface: orchestrating status chip from RoomMeta.background

Design checkpoint 2 of `feature-background-work-working-state`
(Units 4-5 in the feature body — read it for full interfaces, notes, and
acceptance criteria).

## Scope

1. **Room snapshot + parsing** (`app/lib/data/transport/connection_manager.dart`)
   — parse `background` from `room_meta_updated` with the same preserve
   convention as `working`; room snapshot model gains the field.
2. **Projection + indicator** — `ChatStatusProjection` gains a
   `background` axis composed from the active room's snapshot;
   `_ChatStatusIndicator` renders an `orchestrating…` chip
   (`colors.working`) when background is active and the turn status has
   no active label; turn status takes precedence. Composer and Stop
   affordance stay turn-scoped.

## Acceptance evidence

- connection_manager test mirroring the `working` preserve/parse
  contract for `background`.
- Widget test: background + idle turn → 'orchestrating…'; background +
  working turn → 'working…' wins; no background → unchanged.
- `flutter analyze && flutter test --exclude-tags e2e` green from `app/`.

## Ordering

Depends on `story-background-work-ext-tracker` — the wire field must
exist before the app consumes it.

## Implementation notes

- Added the optional background axis to the app room snapshot and parsed it
  through the control-frame boundary, preserving cached state for omitted
  incremental metadata while treating room snapshots as authoritative.
- Composed fresh active-room background state into `ChatStatusProjection` with
  the same online/live-room gating as turn state.
- Added `orchestrating…` rendering for idle, done, and stale turns while
  retaining turn-status precedence; composer and cancellation remain turn-only.
- Files: `app/lib/protocol/control_frames.dart`,
  `app/lib/data/transport/relay_frame_decoder.dart`,
  `app/lib/data/transport/connection_manager.dart`,
  `app/lib/domain/session_state.dart`,
  `app/lib/ui/chat/viewmodels/chat_viewmodel.dart`,
  `app/lib/ui/chat/chat_page.dart`, plus focused transport and widget tests.
- Verification: `flutter analyze`; `flutter test --exclude-tags e2e
  --concurrency=2`; focused connection-manager, widget, and codegen tests.
