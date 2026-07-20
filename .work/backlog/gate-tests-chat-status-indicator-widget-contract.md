---
id: gate-tests-chat-status-indicator-widget-contract
kind: story
tags: [app, testing]
parent: null
depends_on: []
release_binding: null
gate_origin: tests
created: 2026-07-20
updated: 2026-07-20
---

# Protect composed chat status labels at the widget boundary

## Priority
Medium

## Value evidence
Item: `feature-mobile-tui-parity-chat-resilience-status-projection`

Contract / risk / regression / maintenance cost: the release promises that transport, agent-turn, and steering status remain independently visible. `_ChatStatusIndicator` maps all three axes to user-facing labels at `app/lib/ui/chat/chat_page.dart:528-580`. The only AppBar widget test at `app/test/ui/chat/chat_page_appbar_test.dart:104-173` asserts the initial `online` label but never renders reconnecting/offline transport together with waiting/streaming and steering. Domain projection tests protect the data shape, not this final UI mapping, so a future priority-chain regression could again hide waiting or steering while the lower-level tests stay green.

## Gap type
important-interface

## Suggested test
```dart
testWidgets('status indicator renders transport, turn, and steering together', (tester) async {
  // Pump ChatPage with table-driven ChatReady projections.
  // Assert e.g. reconnecting + waiting + steering coexist, and that each
  // label disappears only when its own axis becomes idle/none.
});
```

## Test location (suggested)
`app/test/ui/chat/chat_page_appbar_test.dart`
