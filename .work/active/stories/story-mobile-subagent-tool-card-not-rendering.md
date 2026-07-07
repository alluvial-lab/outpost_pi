---
id: story-mobile-subagent-tool-card-not-rendering
kind: story
stage: drafting
tags: [app, pi-extension, bug, ui]
parent: feature-reconnect-reproduction
depends_on:
  - story-extension-suppress-subagent-assistant-broadcast
release_binding: null
gate_origin: null
created: 2026-07-07
updated: 2026-07-07
---

# Mobile does not render the `subagent` tool card

## Brief

After the subagent text-leak + chatlog-wipe + dispatch-prompt-leak were all
fixed and confirmed (operator: "otherwise passes"), the operator reports the
**`subagent` tool card does not render on the phone side.** The leak/wipe work
is done; this is a separate, smaller visibility issue.

## What's known

- The leak is fully closed: no reply text, no dispatch prompt, chatlog intact.
- The tool card is the only remaining symptom.
- `ToolRequestCard` (`app/lib/ui/chat/widgets/tool_request_card.dart`) renders
  a `ToolEvent` (RUNNING → DONE) from `tool_request` + `tool_result` frames.
- `hideToolCalls` defaults to `false` (`preferences.dart:13`), so ToolEvents
  should render by default — unless the operator has toggled it on (settings
  page exposes it). If toggled on, ALL tool cards hide, not just subagent's.
- `_formatArgs` handles `subagent` via the default branch
  (`args.entries.map((e) => '${e.key}=${e.value}').join(' ')`) — ugly but should
  render *something*. So the card itself should appear (with raw args), unless
  the `ToolEvent` is never created/inserted.

## What's NOT known (needs a capture or operator input)

1. Do the `tool_request`/`tool_result` frames for the `subagent` tool actually
   reach the phone? (The TEMP DEBUG instrumentation was removed after the
   leak/wipe work was confirmed, so there is no capture for the latest
   dispatch.) The earlier capture (pre-cleanup) showed them sent with the
   correct parent session id, but that was a different dist state.
2. Do OTHER tool cards render (bash/read/edit)? If yes → subagent-specific
   (args shape or tool-name handling). If no → broader tool-card issue
   (hideToolCalls toggled, or projection not upserting).
3. Is `hideToolCalls` toggled on in the operator's mobile settings?

## Root cause (HYPOTHESIS — needs confirmation)

Two candidates:
- **Extension-side:** the `tool_request`/`tool_result` for the `subagent` tool
  are not reaching the phone (e.g. gated by accident, or stamped with a session
  id the app rejects). Less likely now that the wipe fix keeps the parent id
  constant, but unverified without a capture.
- **App-side:** the frames reach the phone but the app's transcript projection
  (`transcript_projection.dart` `upsertTool`) does not create/insert a
  `ToolEvent` for the `subagent` tool — e.g. the tool name or args shape fails
  a guard, or the `tool_request`/`tool_result` pairing for an in-process
  subagent doesn't match the projection's `toolCallId` upsert logic.

## Acceptance Criteria

- [ ] Operator confirms: do other tool cards (bash/read/edit) render on
      mobile? Is `hideToolCalls` toggled on?
- [ ] Capture (re-add minimal tool-frame instrumentation, or check the
      existing relay path) whether `tool_request`/`tool_result` for the
      `subagent` tool reach the phone with the correct session id.
- [ ] If they reach the phone: trace the app's `upsertTool` /
      `ToolRequestCard` path to find why the `subagent` ToolEvent isn't
      rendered.
- [ ] Regression test once root cause is confirmed.

## Out of scope

- The subagent text leak / dispatch-prompt leak / chatlog wipe — all FIXED
  (`story-extension-suppress-subagent-assistant-broadcast`,
  `story-extension-subagent-child-session-start-wipes-mobile-chat`).
- The double-messages symptom — separate
  (`story-mobile-double-messages-on-session-history-replay`).

## References

- `app/lib/ui/chat/chat_page.dart:363` — `hideToolCalls` filter;
  `:583` — `ToolEvent() => ToolRequestCard(...)`.
- `app/lib/ui/chat/widgets/tool_request_card.dart` — `_formatArgs` (default
  branch handles `subagent`).
- `app/lib/domain/transcript/transcript_projection.dart:130` — `upsertTool`.
- `app/lib/data/preferences/preferences.dart:13` — `hideToolCalls` default
  false.
- Parent: `feature-reconnect-reproduction.md`.
