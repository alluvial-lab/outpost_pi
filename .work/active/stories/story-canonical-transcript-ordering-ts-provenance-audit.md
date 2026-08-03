---
id: story-canonical-transcript-ordering-ts-provenance-audit
kind: story
stage: implementing
tags: [app, bug]
parent: feature-canonical-transcript-ordering
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-03
updated: 2026-08-03
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
