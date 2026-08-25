---
id: epic-durable-transcript-ownership-durable-event-log
kind: feature
stage: drafting
tags: [pi-extension]
parent: epic-durable-transcript-ownership
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-25
updated: 2026-08-25
---

# F1 — Durable transcript event log (foundation)

## Brief

The extension becomes the authoritative owner of its transcript event log:
custom-entry codec `outpost-pi.transcript-event.v1`, `appendEntry` binding,
`TranscriptEventLog` becomes durable, backfill from `buildContextEntries()`
preferring validated Outpost-Pi events over SDK-derived projection. This is
the epic's architectural foundation — F2/F3/F4 all depend on it.

## Epic context

- Parent: `epic-durable-transcript-ownership` — foundation feature; everything
  else consumes its types and persistence.
- Seed material: the spike verdict + Unit-A design live in
  `story-canonical-transcript-timestamp-ownership-ownership-foundation`
  (read-only spike DONE — feasibility proven; the durable implementation is
  THIS feature's work). Absorb that story's design into the feature-design
  pass and close it as the spike.

## Key constraints from the spike

- Assistant `message_end` fires before `tool_execution_start` → execution ts
  cannot retrofit into SDK-persisted messages → custom-entry path (not reuse).
- `appendEntry` → `SessionManager.appendCustomEntry` → session JSONL →
  recoverable via compaction-aware `buildContextEntries()`.
- SDK messages stay authoritative for LLM context; extension entries for
  transcript.

## Simplification opportunity

Retires the in-memory `TranscriptEventLog` rebuild path once backfill prefers
durable entries — the lossy re-derivation becomes fallback-only (F4 deletes it).
