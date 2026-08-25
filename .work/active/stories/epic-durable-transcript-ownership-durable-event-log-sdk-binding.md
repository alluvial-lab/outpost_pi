---
id: epic-durable-transcript-ownership-durable-event-log-sdk-binding
kind: story
stage: done
tags: [pi-extension]
parent: epic-durable-transcript-ownership-durable-event-log
depends_on: [epic-durable-transcript-ownership-durable-event-log-codec-and-log]
release_binding: v0.8.0
gate_origin: null
created: 2026-08-25
updated: 2026-08-25
---

# Bind durable transcript recording to the fresh SDK appendEntry capability

## Checkpoint

Adapt the current session's `ExtensionAPI.appendEntry` capability to the log's
persistence port. Bind it at factory/replacement lifecycle boundaries, evict it
with other stale capabilities, and keep the existing lossy SDK-message append
path as an explicit fallback until F4.

## Acceptance evidence

- `recordDurableTranscriptEvent(event)` writes exactly
  `appendEntry("outpost-pi.transcript-event.v1", encodedEvent)` and then exposes
  that same event from the in-memory log.
- Missing, stale, or throwing append capabilities return a non-success result,
  do not create an in-memory authoritative event, and do not crash session
  lifecycle handling.
- Session replacement clears the stale writer and a fresh `bindApi`/
  replacement binding restores durable recording.
- Existing producer call sites remain on the named fallback path in F1; F2/F3
  migrate them deliberately rather than F1 silently changing timestamp/native
  event semantics.

## Ordering

Requires the codec/log contract.

## Implementation

- Execution capability: `sol/high` — lifecycle-fresh SDK capability ownership and fail-closed persistence used the caller-selected high-capability path.
- Review weight: not applicable — child story checkpoint.
- Added a distinct `TranscriptEntryApi` guard and a lifecycle-bound persistence adapter that calls public `appendEntry` with the exact v1 discriminator and encoded event.
- Added durable record/timestamp methods while preserving existing producers on the explicitly named fallback path and compatibility wrapper for later F4 retirement.
- Missing/throwing writers fail closed; stale throws evict only the matching writer, shutdown/replacement clears it, and fresh binding restores durable recording.
- Tests: 61 focused projection tests passed; pi-extension typecheck, full 59-file suite (1067 passed, 3 skipped), and build passed.
- Simplification: transcript persistence binding is owned alongside existing message/action capabilities rather than duplicated at producer call sites.
- Discrepancies from design: none.
- Adjacent issues parked: none.
