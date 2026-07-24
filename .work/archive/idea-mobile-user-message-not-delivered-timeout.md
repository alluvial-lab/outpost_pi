---
id: idea-mobile-user-message-not-delivered-timeout
status: superseded
superseded_by: story-fix-resumed-session-echo-gate-rejection
created: 2026-07-03
updated: 2026-07-24
stage: done
release_binding: v0.3.0
tags: [app, pi-extension, bug, lifecycle]
---

# Phone user message shows "not delivered" (20s no-echo timeout)

## Observed

Operator reports user messages on the phone surfacing a "not delivered"
badge. Reported during the same testing window as the pre-pair blank-history
investigation.

## Grounded path

"not delivered" is the app's failed-bubble indicator
(`app/lib/ui/chat/widgets/message_bubble.dart:95`, `UserMsgStatus.failed`).
Two paths set it:

1. **20s no-echo timeout** (`sync_service.dart:289-311`): `_armSendTimeout`
   starts a `pendingSendTimeout` (20s) timer when a user message is sent
   optimistically. If no echo arrives, `_onSendTimeout` → `_failPendingSend`
   (code `send_timeout`, message "Message was not confirmed by the Pi. It
   may not have been delivered.") → `UserMessageFailed` event → "not
   delivered" badge.
2. **Explicit `UserMessageFailed`** from a `Cancelled` server message
   (`sync_service.dart:688-700`). Narrower; only on cancel.

The echo that **clears** it (disarms the timer + confirms the bubble) is a
`user_message` ServerMessage echoed back by the extension with the same
`id` → `UserMessageConfirmed` (`sync_service.dart:605-620`).

## Distinct from

- `idea-extension-stale-ctx-incoming-message-rejected` — that surfaces as a
  ⚠ assistant error bubble (`ErrorMessage` → `AssistantMessageCommitted`
  with `⚠ internal_error: …`, `sync_service.dart:729-757`), NOT a "not
  delivered" user bubble. Different code path, different UI.

## Hypothesis (not confirmed)

If the "not delivered" happens in a **resumed/restarted** session (same
scenario as `story-mobile-chat-blank-on-pair-after-pre-pair-work`), the
user-message echo from the extension may be dropped or sent with a
session_id the app's `SessionGate` rejects (`session_gate.dart`), so the
app never receives its echo → 20s → "not delivered". The backfill fix in
that story addresses *history*, not the *echo path* — but the two are
adjacent and may share a resumed-session root cause. UNCONFIRMED.

## Followup at design time

- Reproduce: pair into a session, send a message from the phone. Time
  whether a `user_message` echo arrives (app logs `[msg-echo] id=…`). If
  no echo in 20s → "not delivered".
- Trace the extension's user-message echo path: on receiving `user_message`
  from the app, does it emit a `user_message` ServerMessage back with the
  same `id` and the current `session_id`? Check `index.ts` `_deliverUserMessage`
  + the `input`/`message_update` echo path.
- Check whether a `SessionGate` rejection (session_mismatch /
  active_session_unknown) silently drops the echo — that would explain a
  no-echo timeout without any visible error.
- Decide if this folds into the resume backfill story or is a separate
  echo-path fix.

## References

- `app/lib/ui/chat/widgets/message_bubble.dart:64-95` — "not delivered" badge.
- `app/lib/data/sync/sync_service.dart:289-337` — send timeout + `_failPendingSend`.
- `app/lib/data/sync/sync_service.dart:605-620` — echo → `UserMessageConfirmed` (disarms timer).
- `app/lib/data/sync/sync_service.dart:729-757` — `ErrorMessage` → ⚠ bubble (the OTHER path; distinct).
- `app/lib/data/sync/session_gate.dart` — session-id gate that may drop the echo.
- `pi-extension/src/index.ts:1962-1971` — `_sendDeliveryError`.
- Related: `.work/active/stories/story-mobile-chat-blank-on-pair-after-pre-pair-work.md`.
- Related: `.work/backlog/idea-extension-stale-ctx-incoming-message-rejected.md` (distinct path).
