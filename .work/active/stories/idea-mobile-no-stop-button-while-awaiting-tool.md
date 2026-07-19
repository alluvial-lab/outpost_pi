---
id: idea-mobile-no-stop-button-while-awaiting-tool
kind: story
stage: done
tags: [app, pi-extension, ux, bug]
parent: feature-mobile-tui-parity-chat-resilience
depends_on: [feature-mobile-tui-parity-chat-resilience-status-projection]
release_binding: null
gate_origin: null
created: 2026-07-02
updated: 2026-07-18
---

# Mobile: agent doesn't show "working" (and no Stop button) while waiting on a tool result

## Observed (refined with operator 2026-07-02)

While the agent is waiting for a `bash` or `background` command to come back,
the mobile app shows the status as **"online"** — same as fully idle — and
there is no Stop button. For contrast, while the model is actively thinking
the app shows **"working."** So the current three-state surface collapses to:

- thinking/streaming tokens → **"working"**
- awaiting tool result → **"online"** (looks idle — wrong)
- actually idle → **"online"**

A distinct **"waiting"** status (or similar) would let the user see the turn
is still active but blocked on a tool, and a Stop button is needed in that
state so the user can interrupt a turn stuck on a long-running tool call.

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
- **Primary UX ask (operator 2026-07-02):** surface a distinct **"waiting"**
  status during `awaitingTool`, separate from both "working" (token
  streaming) and "online" (idle). The `AppTurnStatus.awaitingTool` value is
  already there to drive it — the indicator just needs to read it and render
  a third label/state instead of falling through to "online".
  Candidate vocabulary: `working` (thinking) → `waiting` (awaiting tool) →
  `online` (idle) → `reconnecting` / `offline`. Confirm whether the AppBar
  dot color should also differ for `waiting` (e.g. a third color or a
  pulsing variant) to distinguish blocked-but-active from idle.

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

## Design

**Disposition: structurally subsumed / provenance.** Current source already
passes broad whole-turn `vm.isWorking` to `InputBar.streaming`, so the original
narrow Stop gate has been corrected since capture. The remaining missing
`waiting` phase display and regression proof belong to
`feature-mobile-tui-parity-chat-resilience-status-projection`. Close this item
when that unit proves `working`, `awaitingTool`, and `streaming` all retain a
valid cancel target and Stop affordance while transport is projected
independently.

## Implementation

Closed as provenance for
`feature-mobile-tui-parity-chat-resilience-status-projection`. The composed
status keeps `awaitingTool` active and displays `waiting…`; Stop derives from
the broad turn projection and remains available when the room is online. The
focused ChatViewModel regression proves the cancellation target is retained.
