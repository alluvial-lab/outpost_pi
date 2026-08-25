---
id: epic-durable-transcript-ownership-durable-event-log-codec-and-log
kind: story
stage: done
tags: [pi-extension]
parent: epic-durable-transcript-ownership-durable-event-log
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-25
updated: 2026-08-25
---

# Define the durable transcript codec and log contract

## Checkpoint

Introduce the strict `outpost-pi.transcript-event.v1` custom-entry codec and
make `TranscriptEventLog` own durability through an injected persistence port.
The log must distinguish durable recording from transitional fallback/hydration,
keep first-writer-wins event identity, and expose the winning timestamp for F2.

## Acceptance evidence

- The codec round-trips representative canonical transcript events and rejects
  malformed, non-JSON-safe, unknown-kind, and unexpected-field payloads.
- An unknown `outpost-pi.transcript-event.vN` discriminator is classified as an
  unsupported version and never treated as v1.
- A durable record persists before becoming visible in memory, deduplicates
  before calling persistence, and returns an explicit unavailable/failed result
  without claiming success.
- `recordedTsFor(eventId)` returns only the first accepted event's timestamp;
  hydrate/fallback paths do not write a second custom entry.

## Ordering

Foundation checkpoint; `depends_on: []`.

## Implementation

- Execution capability: `sol/high` — strict persisted-format validation and aggregate durability semantics warranted the caller-selected high-capability path.
- Review weight: not applicable — child story checkpoint.
- Added `durable_transcript_event.ts` with the exact v1 custom discriminator, exhaustive arm validation, recursive JSON-safety checks, and explicit unrelated/unsupported/invalid classification.
- Upgraded `TranscriptEventLog` to persistence-before-visibility recording with observable duplicate/unavailable/failed results, first-writer-wins timestamp indexing, no-write fallback/hydration, and consistent replace/clear rebuilding.
- Tests: 34 focused codec/log cases passed; pi-extension typecheck, full 59-file suite (1061 passed, 3 skipped), and build passed.
- Simplification: one event-id map now owns dedupe and timestamp lookup; no parallel `seen`/timestamp indexes.
- Discrepancies from design: none.
- Adjacent issues parked: none.
