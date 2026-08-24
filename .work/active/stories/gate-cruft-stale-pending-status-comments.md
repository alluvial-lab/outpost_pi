---
id: gate-cruft-stale-pending-status-comments
kind: story
stage: implementing
tags: [cleanup]
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: cruft
created: 2026-08-24
updated: 2026-08-24
---

# Correct pre-reconnect semantics in pending-message comments

## Confidence
High

## Category
stale comment

## Location
- `app/lib/domain/session_state.dart:14-18`
- `app/lib/ui/chat/widgets/message_bubble.dart:19-22`

## Finding
The domain and widget comments still describe `pending` as a message already
sent over WebSocket and describe failure as a fixed 15-second no-echo result.
The reconnect/identity-window implementation now intentionally keeps both
identity-blocked messages and offline/room-not-live messages pending before any
channel write, and the actual timeout is injected (`pendingSendTimeout`, 20 seconds
by default). The comments therefore misstate both the state transition and its
user-visible timing.

## Evidence
```dart
/// lifecycle stage of its rebroadcast. `pending` = sent over WS but Pi
/// hasn't echoed it back yet; `confirmed` = Pi rebroadcast it (or it
/// came from `session_history` / another device's echo); `failed` =
/// 15s elapsed without echo, user can retry.
```

```dart
// the bubble. `pending` (sent over WS, Pi hasn't echoed yet) gets
// reduced opacity + a small spinner; `failed` (no echo in 15s) gets
// a red exclamation badge so the user knows to retry.
```

## Removal rationale
Remove the plan-era sent/15-second claims and document the current contract:
pending means not yet confirmed and may be held before transport or awaiting an
echo; failed is produced by the configured pending-send backstop. Keep the visual
behavior and status enum unchanged.

## Risk
Documentation-only. Leaving the comments unchanged risks agents and maintainers
reintroducing the old swallow-window assumptions or treating a held pending row as
already delivered.
