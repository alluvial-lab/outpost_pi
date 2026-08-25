---
id: epic-durable-transcript-ownership-durable-event-log-codec-and-log
kind: story
stage: implementing
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
