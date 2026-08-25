---
id: epic-durable-transcript-ownership-durable-native-events
kind: feature
stage: drafting
tags: [pi-extension]
parent: epic-durable-transcript-ownership
depends_on: [epic-durable-transcript-ownership-durable-event-log]
release_binding: null
gate_origin: null
created: 2026-08-25
updated: 2026-08-25
---

# F3 — Durable-ize Outpost-Pi-specific transcript events

## Brief

Mesh tool cards, compaction markers, tool-request-as-distinct-from-result,
steering events — currently in-memory only, lost on restart — become durable
via F1's codec. Ground-truth gap table:
`story-canonical-transcript-ordering-systematic-ts-provenance-sweep` (drafting —
its enumeration feeds this feature; close it into F3's design).

## Epic context

Consumer of F1's codec + append path. Independent of F2 (parallelizable).

## Simplification opportunity

Deletes the in-memory-only event kinds entirely; no dual representation.
