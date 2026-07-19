---
id: idea-mobile-chat-reorder-on-return
kind: story
stage: done
tags: [app, bug, lifecycle]
parent: feature-mobile-tui-parity-chat-resilience
depends_on: [idea-mobile-queued-message-does-not-reorder]
release_binding: null
gate_origin: null
created: 2026-07-03
updated: 2026-07-18
---

# Returning to a chat sometimes reorders the latest user message below the assistant response

## Observed

When returning to a chat (back out to session list → re-enter, or app
resume → re-enter), the latest user message sometimes renders **below** the
assistant's response to it — i.e. prompt appears after its own response,
out of logical order. The canonical order is user-prompt-then-assistant-
response; on return the row order is inverted for the latest exchange.

## Distinct from

- `idea-mobile-queued-message-does-not-reorder` — that is a **steering**
  symptom: a message sent mid-turn stays above the in-flight assistant
  output and doesn't relocate to the bottom on pickup. This item is a
  **return/rehydrate** symptom: ordering is wrong on re-entry, not on
  steering pickup. Both may share the seq-then-eventId sort root cause
  (see below) but have different triggers and likely different fixes.

## Likely surface (not confirmed — bounded scan only)

The app orders messages by `seq` then `eventId`
(`app/lib/data/local/transcript_event_store_hive.dart:74-76`):

```dart
records.sort((a, b) {
  final seqCompare = a.seq.compareTo(b.seq);
  return seqCompare == 0 ? a.eventId.compareTo(b.eventId) : seqCompare;
});
```

On return to a chat, `_loadIndex` + the transcript projection rebuild the
view from the local event store
(`app/lib/data/sync/sync_service.dart:1094-1120`, `_materializeTranscriptProjectionForRef`).
If the latest user-message event was appended to the store with a **higher
seq** than the assistant-response event (e.g. the assistant response was
stored first — from a live streaming chunk or a replay batch that arrived
before the user echo was confirmed), the seq sort places the user bubble
below the response. Re-entering the chat re-runs the sort over persisted
rows, so the wrong order is stable until a fresh replay rewrites seqs.

So the suspected gap: **row order derives from append seq, not from a
prompt/response logical ts**, and a return-to-chat re-projection exposes an
ordering that live view masked or that drifted during the original session.

## Followup at design time

- Reproduce: in a live chat, send a message, get a response, back out to
  the session list, re-enter. Confirm whether the latest exchange is
  inverted. Try with a fast assistant reply (streaming chunk stored before
  user echo?) and a slow one.
- Trace the seq assignment for the latest user message vs its assistant
  response in the event store: does the user event get a higher seq? Is
  the assistant chunk persisted before the user echo on the live path?
- Decide the fix layer: (a) order by event `ts` (logical time) instead of
  append `seq`, with seq only as a tiebreaker; (b) re-stamp the user
  message's seq when its response is picked up (mirrors the queued-message
  reorder fix shape); (c) view-layer reorder. Prefer deriving order from
  one authoritative field (single-source-of-truth rule,
  `.agents/rules/code-design.md`) — likely `ts`, since that's the logical
  prompt/response order and is stable across rehydrate.
- Coordinate with `idea-mobile-queued-message-does-not-reorder`: both are
  ordering-semantics gaps over the same sort; a single ordering-model fix
  (ts-based, with a queued-pickup re-anchor) may resolve both. Consider
  scoping them together at design time.

## References

- `app/lib/data/local/transcript_event_store_hive.dart:74-76` — seq-then-eventId sort.
- `app/lib/data/sync/sync_service.dart:1094-1120` — `_loadIndex` (re-projection on return).
- `app/lib/data/sync/sync_service.dart:829-840` —
  `_materializeTranscriptProjectionForRef` (rebuild view from store).
- `app/lib/data/sync/session_history_replay.dart` — replay event ids carry
  the server `ts`; usable as a logical-order key.
- `.agents/skills/flutter-mobile/SKILL.md` — async UI safety, rehydrate.
- Sibling: `.work/backlog/idea-mobile-queued-message-does-not-reorder.md`.
- Parent structural finding: `.work/backlog/idea-mobile-conflates-transport-and-agent-state.md`.

## Design

**Disposition: distinct bug / implementation Unit 3.** First reproduce with a
controlled event order covering optimistic submit, early echo, assistant
commit, canonical user confirmation, cold read, and repeated history replay.
If current deterministic identities already preserve order, close with that
regression evidence and no production edit. Otherwise derive UI order in the
pure transcript projection from stable message identity and `replyTo`/pickup
relationships. Keep append `seq` as event-log replay order; reject a global
wall-clock sort, stored-seq mutation, or a second widget-layer sorter. Live,
cold-read, and replay projections must return identical IDs and order.

## Implementation

Pinned the adverse append order directly: optimistic prompt, assistant commit,
then late canonical prompt confirmation. The pure transcript projection now
applies one narrow semantic constraint—move a prompt before assistant rows whose
stable `replyTo` names it—while preserving event-log `seq` and every unrelated
row's relative order. Duplicate/replayed events produce the same IDs and order;
no wall-clock sort, stored-seq rewrite, or widget-layer sorter was added.

Scoped analysis and transcript, history-replay, and full SyncService targeted
tests pass serially.
