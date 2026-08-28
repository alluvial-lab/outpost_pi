---
id: story-offline-state-liveness-ux
kind: story
stage: done
tags: [app, ux, bug]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-27
updated: 2026-08-27
---

# Offline state must look alive — retry liveness + unreachable-cause hint

## Brief

The app's reconnect machinery is proven sound, but an undifferentiated
offline banner makes a correctly-retrying app look wedged. When the relay
is unreachable for minutes, the operator cannot distinguish "retrying with
backoff" from "stuck until force-close" — and reads it as the latter. The
connection status surface must expose retry liveness and, where the failure
shape allows it, a pointed cause hint.

Field evidence (capture 2026-08-27T22-34: 15 minutes of continuous
connect-failures at 30s backoff — phone-side tailnet/VPN drop — read by
the operator as "app stuck offline until force-close"). Behavior was
CORRECT (retry ladder never stopped; self-recovered at 22:32:37 the moment
the path returned) but experientially dead.

## Work

- After N consecutive failed connect attempts: surface liveness —
  last-attempt timestamp + next-retry countdown in the connection status
  surface.
- After N consecutive WebSocketChannelException (TCP-level) failures
  specifically: add the pointed hint — "Can't reach the relay — check
  Tailscale/VPN" (distinguish transport-unreachable from
  relay-rejecting/auth failures, which should hint differently).
- Consider a manual "retry now" affordance in the same surface.

Not a correctness blocker; the reconnect machinery is proven sound
(capture: re-arm intact through 3h churn incl. extension restart).

## Code seams (grounded at scope time)

- `app/lib/data/transport/connection_manager.dart` — retry ladder; the
  connect-attempt accounting added by `story-connect-attempt-deadline`
  (v0.10.1) is the natural source for attempt counts/deadline state —
  reuse it rather than adding parallel counters.
- `app/lib/data/transport/ws_transport.dart` — where
  `WebSocketChannelException` (transport-level) is distinguishable from
  relay close codes / auth rejection; failure classification lives here.
- `app/lib/ui/chat/viewmodels/chat_viewmodel.dart` (`statusProjection`) and
  the `_ChatStatusIndicator` widget in `app/lib/ui/chat/chat_page.dart` — the
  connection status surface the liveness/countdown/hint renders into.
  (Seam names corrected 2026-08-27: an earlier grep artifact recorded
  `_nlIndicator`; the real widget is `_ChatStatusIndicator`.)

## Simplification opportunity

Reuse the v0.10.1 connect-attempt accounting instead of new retry-counter
state; if `connection_manager` and `ws_transport` both classify failures
after this change, consolidate the classification in one place. The
"retry now" affordance is optional — cut it if it complicates the status
surface.

## Verification

`flutter analyze && flutter test --exclude-tags e2e` from `app/`; add
widget/viewmodel tests for the countdown projection and the
transport-vs-auth hint split.

## Implementation notes

- Landed retry liveness through the existing `ReachabilityAdapter` attempt
  ladder: `StatusRetrying` now carries the last-attempt time, absolute retry
  deadline, failure classification, and classified failure streak. The chat
  ViewModel projects those fields and the chat status surface renders a
  ticking countdown plus the last-attempt time.
- Thresholds are deliberately two consecutive failures: liveness appears
  after two failed attempts, and the Tailscale/VPN hint appears after two
  consecutive transport failures. A relay rejection/authentication failure
  gets its pairing/auth hint after the first classified rejection because it
  is actionable immediately. WebSocket/TCP classification remains in
  `ws_transport.dart`; the connection manager only consumes the result.
- The manual “retry now” affordance was cut. The existing retry ladder remains
  the sole reconnect owner, keeping the status surface focused and avoiding a
  second path that could race the scheduled attempt.
- Files touched: `app/lib/domain/value_objects/reachability.dart`,
  `app/lib/data/transport/reachability_adapter.dart`,
  `app/lib/data/transport/ws_transport.dart`,
  `app/lib/data/transport/connection_manager.dart`,
  `app/lib/domain/session_state.dart`,
  `app/lib/ui/chat/viewmodels/chat_viewmodel.dart`,
  `app/lib/ui/chat/chat_page.dart`, and the corresponding transport/chat tests
  under `app/test/`.
- Verification: `flutter analyze` passed; `flutter test
  --exclude-tags e2e --concurrency=2` passed with 994 tests. Targeted
  transport/ViewModel/widget tests also passed. Dart format was run only on
  the touched Dart files.
