---
id: idea-mobile-queued-message-does-not-reorder
kind: story
stage: done
tags: [app, pi-extension, ux, bug]
parent: feature-mobile-tui-parity-chat-resilience
depends_on: [feature-mobile-tui-parity-chat-resilience-status-projection]
release_binding: v0.2.0
gate_origin: null
created: 2026-07-02
updated: 2026-07-20
---

# Mobile: steered message threads into output in place; doesn't reorder to bottom when picked up

## Observed (with screenshot)

When the user sends a message while the agent is mid-turn (steering), the
mobile app threads the user bubble into the conversation **at the point it was
sent** — above the assistant's continued output — and it does **not** "move"
to the bottom when the agent finishes the current prompt and picks up the new
one. So on mobile it looks out of order: the user's new prompt appears above
the assistant's response to the *previous* prompt.

In the pi TUI, the new prompt queues and then **reorders to the bottom** once
it's picked up for thinking — the canonical ordering is prompt-then-response,
not insertion-seq-order.

Screenshot (`img_650f990d`) confirms: the user's feedback bubble is at the
top of the visible list, with the assistant's monospaced code-analysis
response below it (the response to the *prior* prompt). No "queued"/"steering"
indicator near the user bubble.

## Root cause (grounded)

The app orders messages by `seq` then `eventId`
(`app/lib/data/local/transcript_event_store_hive.dart:74-76`):

```dart
records.sort((a, b) {
  final seqCompare = a.seq.compareTo(b.seq);
  return seqCompare == 0 ? a.eventId.compareTo(b.eventId) : seqCompare;
});
```

A steered user message gets a seq at the point it was received, so it lands
**above** the in-flight assistant output that follows it in seq order. The pi
TUI evidently re-anchors a queued/steered message to the position where the
agent *picks it up* (bottom, at the start of the next turn) rather than where
it was received. The app renders strict insertion order; the TUI renders
logical prompt/response order.

So this is an **ordering-semantics** gap, not just a missing indicator.

## Relationship to other findings

- This is the third symptom of the parent structural finding
  `idea-mobile-conflates-transport-and-agent-state` — the app has no first-
  class "queued" agent state, so it has no point at which to reorder the
  queued message from "received-here" to "picked-up-here."
- Sibling: `idea-mobile-no-steering-indicator-when-queued` (the indicator);
  this item is the reorder behavior. Both need the app to model "queued,
  not yet picked up" as a distinct state.

## Followup at design time

- Decide the reorder trigger: when does the queued message move to the bottom?
  On `turn_start` for the new turn (i.e. when the agent picks it up)? On
  `queued_message_clear` / `user_message` rebroadcast? Confirm the extension
  events that mark the transition from queued → active-prompt.
- Two implementation shapes: (a) assign the user message a new seq/position
  when picked up (re-write on reorder), or (b) keep seq stable but render
  queued messages in a "pending" slot that relocates on pickup. (a) is simpler
  but mutates stored order; (b) is a view-layer reorder. Consider the
  single-source-of-truth rule — order should derive from one field, not a
  view-layer override of stored seq.
- Cross-check the pi TUI's reorder behavior to mirror its exact semantics
  (does it move on pickup, on turn_start, or on first token of the response?).

## References

- `app/lib/data/local/transcript_event_store_hive.dart:74-76` — seq-then-
  eventId sort (insertion order, no pickup reorder).
- `app/lib/ui/chat/viewmodels/chat_viewmodel.dart:185` — `_messages = [for
  (final r in rows) r.toChatMessage()]` (renders repository order directly).
- `pi-extension/src/session/sdk_session_projection.ts:509-513` —
  `queued_message_clear` → delivers the queued message as `user_message`
  (the pickup event that should trigger reorder).
- Screenshot `img_650f990d` — user bubble above assistant's continued output.

## Design

**Disposition: distinct bug / implementation Unit 2.** The status split enables
a visible pending→picked-up transition but does not itself change transcript
placement. Record early steer acceptance as delivery/pending metadata on the
existing user transcript event; do not anchor a chat row until the canonical
timestamped user-input pickup arrives. Pickup clears the steering indicator and
materializes exactly one prompt after the prior response. Repeated early echoes,
pickup events, and replay must collapse by stable identity. Metadata is additive
with backward-compatible defaults; do not rewrite Hive `seq` or infer pickup
from elapsed time.

## Implementation

Added optional `awaitingPickup`/`semanticPickup` transcript metadata. A steered
submission and its early no-timestamp acceptance now project one typed pending
steering overlay without a chat row; the later deterministic timestamped
`user_input` materializes the row at pickup and clears the overlay. Duplicate
echoes/replay collapse by stable identity, failures surface one failed row, and
old records default to canonical placement. Hive append `seq` remains untouched.

The extension contract test now proves the early steer echo is followed by a
`message_end`-owned timestamped `user_input` carrying the same client ID.
Scoped analysis and the transcript/store/SyncService/ChatViewModel test set pass.
