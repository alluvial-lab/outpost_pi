---
id: epic-durable-transcript-ownership-durable-event-log-backfill-reopen
kind: story
stage: implementing
tags: [pi-extension]
parent: epic-durable-transcript-ownership-durable-event-log
depends_on: [epic-durable-transcript-ownership-durable-event-log-sdk-binding]
release_binding: null
gate_origin: null
created: 2026-08-25
updated: 2026-08-25
---

# Reconcile durable entries on compaction-aware reopen

## Checkpoint

Replace restart backfill's `buildSessionContext().messages` read with the active
`buildContextEntries()` branch. Decode durable Outpost-Pi entries first,
suppress only their matching SDK-derived transcript projections, and retain the
SDK projection as the migration/failure fallback for sessions without valid
v1 entries.

## Acceptance evidence

- Mixed active branches replay in entry order while validated durable user/tool
  facts win over matching SDK-derived facts; invalid or unsupported entries do
  not suppress fallback events.
- Raw compaction entries still project to `compaction_recorded`, and only the
  SDK's active compaction-aware branch is hydrated.
- A real file-backed `SessionManager` record survives `SessionManager.open()`
  and a fresh fake-SDK replacement harness instance with canonical event
  identity and timestamp intact, including multiple tool calls in one assistant
  message.
- Corrupt v1 data, an unknown version, and a truncated final JSONL custom-entry
  line reopen without crashing; recoverable SDK message history remains
  available.
- A mixed pre-upgrade/in-flight session needs no rewrite: old SDK-only history
  falls back, while later valid custom entries are preferred.

## Ordering

Requires the SDK durability binding.
