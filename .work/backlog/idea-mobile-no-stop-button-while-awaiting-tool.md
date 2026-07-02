---
id: idea-mobile-no-stop-button-while-awaiting-tool
created: 2026-07-02
updated: 2026-07-02
tags: [app, pi-extension, ux, bug]
---

# Mobile: agent doesn't show "working" (and no Stop button) while waiting on a tool result

## Observed

While the agent is waiting for a `bash` or `background` command to come back,
the mobile app does not show the agent as "working," and there is no Stop
button in that state. The user can't interrupt a turn that's blocked on a
long-running tool call. This is "technically accurate" (the model isn't
streaming tokens) but poor UX: the user has no indication the turn is still
active and no way to cancel it.

## Root cause (bounded scan — projection gap, not data gap)

The app domain model already has the right vocabulary:

- `AppTurnStatus` has `awaitingTool` distinct from `streaming`/`working`
  (`app/lib/domain/session_state.dart`).
- The `working` getter on `AppTurnProjection` correctly includes
  `awaitingTool` → `true` (so `cancelTargetId` is set during tool waits).
- The streaming *bubble* uses the broad `working` signal
  (`lib/ui/chat/chat_page.dart:392`: "the WHOLE working turn … not just the
  narrow token-streaming window").

But **two projections use the narrow `streaming` flag instead of broad
`working`**:

- `InputBar.streaming` (`lib/ui/chat/widgets/input_bar.dart:38` —
  `streaming; // show cancel instead of send`). The Stop button is gated on
  `streaming`, so it disappears during `awaitingTool`.
- The AppBar status dot logic (`lib/ui/chat/chat_page.dart:170-182`) appears to
  derive "working" from a narrow signal; confirm whether it covers
  `awaitingTool` or only token-streaming.

So during a bash/background wait: `streaming == false` (no tokens flowing) but
`working == true` (turn is active, tool pending). The Stop button vanishes and
the working indicator may go idle — even though the turn is live and
interruptible.

## Followup at design time

- Gate the Stop button on the **broad `working` signal** (the same one the
  streaming bubble uses), not the narrow `streaming` flag. The
  `cancelTargetId` is already populated whenever `working` is true
  (including `awaitingTool`), so the cancel plumbing exists.
- Confirm the AppBar status dot derives "working…" from the broad signal too,
  so the dot stays lit during tool execution.
- Check that cancel-during-`awaitingTool` routes to the extension's abort
  path (`pi-extension/src/index.ts` `_abortCurrentTurn`, `cancel` message in
  `_routeClientMessageFrom`). The app sends `cancel`; confirm it interrupts a
  tool-blocked turn and not just token streaming.
- Consider distinct UX for `awaitingTool` (e.g. "running tool…" vs
  "working…") so the user sees the agent is blocked on a tool, not idle —
  the `AppTurnStatus.awaitingTool` value is already there to drive it.

## References

- `app/lib/domain/session_state.dart` — `AppTurnStatus.awaitingTool`, the
  `working` getter (includes `awaitingTool`), `cancelTargetId`.
- `app/lib/ui/chat/widgets/input_bar.dart:38` — `streaming` gates the Stop
  button (should be `working`).
- `app/lib/ui/chat/chat_page.dart:170-182,392` — status dot derivation vs
  streaming bubble's broad working signal.
- `pi-extension/src/index.ts` — `_abortCurrentTurn`, `cancel` handling in
  `_routeClientMessageFrom`.
- `.agents/skills/scan-lifecycle/SKILL.md` — "working state converges false
  on every exit path" (the inverse concern: ensure broadening the Stop gate
  doesn't leave a stuck Stop button if `awaitingTool` never resolves).

Distinct from `idea-mobile-no-steering-indicator-when-queued` (that's the
queued-message indicator gap; this is the Stop-button + working-indicator gap
during tool execution).
