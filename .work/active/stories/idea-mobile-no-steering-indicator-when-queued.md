---
kind: story
release_binding: null
parent: feature-mobile-tui-parity-chat-resilience
stage: drafting
id: idea-mobile-no-steering-indicator-when-queued
created: 2026-07-02
updated: 2026-07-02
tags: [app, pi-extension, ux, bug]
---

# Mobile: no "steering/queued" indicator when sending a message while agent is working

## Observed

When the user sends a message while the agent is mid-turn, the mobile chat
shows no difference between "working on the last prompt" and "message
received — queued behind the current turn." In a pi TUI session, a gray
"steering" indicator appears until the agent finishes the current prompt and
picks up the new one. The mobile app lacks this affordance, so the user can't
tell whether their interjection was received and queued or ignored.

## What already exists (data path is wired — gap is UX projection)

The app **has** the queued/steering concept end-to-end; it's just not surfaced
as a distinct indicator:

- Extension publishes `queued_message_state` / `user_input` events
  (`pi-extension/src/session/sdk_session_projection.ts:468` `queuedMessageState`,
  `pi-extension/src/index.ts:1154` `pi.on("input")`, `:1170` broadcasts
  `user_input`).
- App receives them: `lib/protocol/generated/protocol.g.dart` has
  `QueuedMessageSet` / `QueuedMessageClear`; `ChatViewModel` has
  `setQueued`/`clearQueued`; `SyncService` has `setQueued`/`clearQueued` and
  a `steer` streaming-behavior path.
- `InputBar` supports sending steering text while streaming
  (`lib/ui/chat/widgets/input_bar.dart`: "During streaming, empty composer
  shows Stop; typed text sends steering").

But the status indicator only distinguishes `working` / `reconnecting` /
`online` / `offline` (`lib/ui/chat/chat_page.dart:170-182`). There is no
distinct "steering" / "queued message pending" visual. So a queued message
looks identical to plain working.

## Followup at design time

- Decide the mobile affordance for "queued behind current turn": a gray
  steering dot/banner (mirroring the pi TUI), a queued-message bubble preview,
  or both. The `queuedText` already flows into `InputBar` (`queuedText`
  field, `onSetQueued`/`onClearQueued`) — check whether it's rendered at all
  or just held as state.
- Confirm the app actually requests `steer` streaming behavior when sending
  during a working turn (vs always `append`/`auto`), since that determines
  whether the extension queues or interrupts. See
  `pi-extension/src/index.ts:1982` `requestedSteer` and
  `lib/data/sync/sync_service.dart` `isSteer`.
- The pi TUI's gray steering indicator is the reference UX to mirror.

## References

- `app/lib/ui/chat/chat_page.dart:170-182` — status indicator vocabulary
  (working/reconnecting/online/offline only).
- `app/lib/ui/chat/widgets/input_bar.dart` — `queuedText`, steering send path.
- `app/lib/ui/chat/viewmodels/chat_viewmodel.dart` — `setQueued`/`clearQueued`.
- `app/lib/data/sync/sync_service.dart` — `setQueued`/`clearQueued`, `isSteer`.
- `pi-extension/src/session/sdk_session_projection.ts:468` —
  `queuedMessageState`.
- `pi-extension/src/index.ts:1154,1170,1982` — `input` event, `user_input`
  broadcast, `requestedSteer`.

Distinct from `idea-mobile-no-stop-button-while-awaiting-tool` (that's the
Stop-button-during-tool-execution gap; this is the queued-message indicator
gap).
