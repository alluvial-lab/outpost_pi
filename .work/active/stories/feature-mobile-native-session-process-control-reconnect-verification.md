---
id: feature-mobile-native-session-process-control-reconnect-verification
kind: story
stage: done
tags: [app, pi-extension]
parent: feature-mobile-native-session-process-control
depends_on: [idea-mobile-session-control, idea-mobile-restart-pi-session-affordance]
release_binding: null
gate_origin: null
created: 2026-07-18
updated: 2026-07-18
---

# Verify mobile session/process control reconnect behavior

## Brief

Add the focused cross-surface verification for the mobile session controls. This
story does not introduce a new protocol action or process-management path; it
proves that the existing `session_new` request and daemon exit-42 contract are
safe to expose through the new Quick Actions affordance.

## Design

### Implementation unit

Cover the smallest useful boundaries after the two control stories land:

- `app/test/data/actions/actions_repository_test.dart` — the generated
  `SessionNew` frame, active session binding, matching `action_ok`, and
  rejection/timeout behavior.
- `app/test/ui/chat/quick_actions/quick_actions_sheet_test.dart` — New session
  and Restart Pi confirmation/cancel paths, busy/double-submit prevention,
  reset only after acknowledgement, and failure feedback without transcript
  loss.
- Existing app sync/reconnect test seams — successor room/session metadata is
  authoritative after the expected process disconnect, and late frames from
  the old session do not repopulate the new transcript.
- Focused `pi-extension/src/**/*.test.ts` — daemon-mode `action_ok` is emitted
  before the scheduled `EXIT_DAEMON_FRESH_SESSION` exit and the successor
  publishes the same paired room/identity with a fresh session.

Use deterministic fake channels/timers where available. A live supervisor/phone
smoke may be documented separately, but must not be substituted for boundary
unit tests or made green by broad mocks.

### Implementation

- Added explicit `session_new` session-id binding and matching rejection
  coverage to the app action repository tests.
- Added Quick Actions tests for both destructive confirmations, cancellation,
  ACK-gated local reset, rejection preservation, and reconnect feedback using a
  controlled completer rather than a timing delay.
- Verified the existing extension daemon path remains the canonical
  `action_ok` → session reset → scheduled exit 42 flow; no extension production
  or wire changes were needed for this app-only affordance.
- Reconnect remains owned by the existing ConnectionManager/SyncService state
  machine and authoritative room/session hydration; the UI feedback is only a
  transient snackbar, not a sticky restart state.

## Acceptance criteria

- The app proves both destructive controls dispatch the canonical `session_new`
  action only after confirmation.
- A rejected or timed-out action leaves the local transcript intact; a matched
  ACK permits the expected local reset and reconnect feedback.
- The extension proves ACK-before-exit ordering and preserves room/identity
  continuity across the supervisor respawn.
- Reconnect hydration establishes the new session from authoritative snapshots;
  stale old-session frames are ignored.
- No `/reload`, `session_restart`, arbitrary slash-command, or new spawn API is
  introduced as a testing shortcut.
