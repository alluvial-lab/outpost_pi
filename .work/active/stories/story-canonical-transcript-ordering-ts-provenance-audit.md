---
id: story-canonical-transcript-ordering-ts-provenance-audit
kind: story
stage: done
tags: [app, bug]
parent: feature-canonical-transcript-ordering
depends_on: []
release_binding: v0.4.0
gate_origin: null
created: 2026-08-03
updated: 2026-08-11
---

# Audit remaining live DateTime.now() paths for ts provenance

Unit 4 of `feature-canonical-transcript-ordering`. The render sort (Unit 3) is
only correct if EVERY authoritative-bubble-producing event carries a canonical
server `ts` on the live path (or is provably excluded from the render list).
The cross-model review flagged several live `DateTime.now()` paths beyond
tools. Audit and close each.

## Scope

`app/lib/data/sync/sync_service.dart`, the live `DateTime.now()` event-creation
paths:

- `UserInput` without `ts` (~:1016-1067) — does the wire carry a server `ts`
  here? If not, does the resulting `UserMessageConfirmed`/`UserMessageSubmitted`
  enter the authoritative render list?
- Legacy / error assistant commits (~:1296-1299).
- `AssistantDeltaReceived` (~:894) — CONFIRM excluded (it only sets
  `streaming`, never enters `authoritativeMessages`) and document.

## Change

For each path: either thread the server `ts` the wire already provides, or
record in this story + a code comment why the event is excluded from the
authoritative render sort. Fix any path found to leak phone `ts` into an
authoritative bubble, with a test. (Deltas are expected to be confirmed-excluded;
no change needed there beyond the note.)

## Acceptance

- [ ] Audit table in this story body: each live event-creation site →
  `{kind, ts source, enters authoritative list? (y/n), action}`.
- [ ] Every authoritative-bubble-producing kind carries server `ts` on the live
  path OR is documented as render-excluded.
- [ ] Any leak found is fixed + covered by a test; `flutter analyze` clean.

## Ordering

`depends_on: []` — runs in parallel with Unit 1 (independent app-only audit).
Must close before the feature closes (it is the gate on the "single-clock"
invariant Unit 3 relies on).

## Audit

`authoritative?` means the event contributes to `authoritativeMessages` in
`deriveTranscriptProjection`; `DateTime.now()` below is retained only as the
optional-wire-field compatibility fallback for old extensions.

| Site / event kind | ts source | authoritative? | Action |
| --- | --- | --- | --- |
| Local send → `UserMessageSubmitted` (~378) | Phone send-time `DateTime.now()` | n | Confirmed optimistic only: it remains in `localTail` until confirmation and never enters `authoritativeMessages`. No change. |
| Send failure/cancellation → `UserMessageFailed` (~548, ~1190) | Phone receipt `DateTime.now()` | n | Confirmed failure overlay only; failed submissions are not authoritative bubbles. No change. |
| `AgentChunk` → `AssistantDeltaReceived` (~894) | Phone receipt `DateTime.now()` | n | Confirmed excluded: this event only updates `streaming`; it never enters `authoritativeMessages`. No change. |
| `AgentDone` fallback → `AssistantMessageCommitted` (~935) | `AgentDone.ts` when present; phone `DateTime.now()` only when an old frame omits it | y | Fixed to consume the server `ts`; compatibility fallback retained and covered by a focused test. |
| `AgentDone` → `AssistantDoneReceived` (~946) | Phone receipt `DateTime.now()` | n | Confirmed excluded: completion state only; it does not render a bubble. No change. |
| `AgentMessage` with `ts` (~991) | Server `AgentMessage.ts` | y | Already canonical; deterministic live/replay identity path unchanged. |
| Legacy `AgentMessage` without `ts` (~1016) | Phone receipt `DateTime.now()` | y | No server timestamp exists on this old wire frame; retained as the documented optional-`ts` compatibility fallback. |
| `UserInput` → `UserMessageConfirmed` (~1062) | Server `UserInput.ts` when present; phone `DateTime.now()` when absent | y for semantic pickup; n for `semanticPickup: false` steering confirmations | Already consumes server `ts`; the absent-field fallback is required for old extensions. Steering confirmations are held out of the authoritative list by the projection. |
| `ErrorMessage` → diagnostic `AssistantMessageCommitted` (~1296) | Phone receipt `DateTime.now()` | y (rendered diagnostic) | `ErrorMessage` has no server `ts` field and no `session_history` counterpart, so this is a local diagnostic compatibility bubble rather than a canonical history event. No wire/schema change in this app-only story. |
| `ErrorMessage` → `AssistantDoneReceived` (~1304) | Phone receipt `DateTime.now()` | n | Confirmed excluded completion marker. No change. |
| `Compaction` → `CompactionRecorded` (~1318) | Server `Compaction.ts` when present; phone `DateTime.now()` when absent | y | Already consumes server `ts`; absent-field fallback retained for compatibility. |

Tool request/result event creation and the assistant-text flush immediately
before a tool are deliberately excluded from this audit: Unit 1 owns the wire
field and Unit 2 owns all tool consumption in this same service. Their current
phone-clock fallbacks remain compatibility behavior until those units land.

## Implementation notes

The live authoritative fallback commit now uses `AgentDone.ts` when available;
all other authoritative paths already consume their available server `ts`, with
local receipt time retained only where the optional wire field is absent or the
message is a local diagnostic with no canonical history timestamp.
