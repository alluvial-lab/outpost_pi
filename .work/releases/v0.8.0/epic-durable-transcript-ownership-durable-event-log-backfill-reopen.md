---
id: epic-durable-transcript-ownership-durable-event-log-backfill-reopen
kind: story
stage: done
tags: [pi-extension]
parent: epic-durable-transcript-ownership-durable-event-log
depends_on: [epic-durable-transcript-ownership-durable-event-log-sdk-binding]
release_binding: v0.8.0
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

## Implementation

- Execution capability: `sol/high` — two-pass semantic reconciliation, mixed-version migration, and real SDK JSONL reopen behavior used the caller-selected high-capability path.
- Review weight: not applicable — child story checkpoint.
- Replaced transcript backfill with one `buildContextEntries()` active-branch read and a pure two-pass mapper: valid v1 entries are decoded/re-homed first, then only matching SDK transcript projections are suppressed in entry order.
- Added semantic tool collision matching, cardinality-preserving FIFO user matching for repeated equal prompts, event-id matching for ordinary facts, raw compaction mapping, and invalid/unsupported-entry fallback behavior.
- Extended the fake SDK harness so `appendEntry` delegates to its real `SessionManager`; file-backed tests cover reopen identity/timestamp equivalence, two tool calls, corrupt v1, unknown version, and an actually truncated final JSONL line.
- Hardened the codec against explicit `undefined` optional properties and accessor failures found while exercising corrupt-entry reconciliation.
- Tests: 108 focused codec/projection/replacement cases passed; pi-extension typecheck, full 59-file suite (1076 passed, 3 skipped), and build passed.
- Simplification: restart backfill now maps the active context-entry stream once and hydrates the aggregate; `buildSessionContext()` remains only in the explicit legacy adapter/test surfaces.
- Discrepancies from design: none.
- Adjacent issues parked: none.
