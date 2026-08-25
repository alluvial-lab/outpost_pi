---
id: gate-tests-durable-reopen-topology-interleavings
kind: story
stage: implementing
tags: [testing, pi-extension]
parent: null
depends_on: []
release_binding: v0.8.0
gate_origin: tests
created: 2026-08-25
updated: 2026-08-25
---

# Exercise durable transcript reopen across deep forks, compaction, and producer interleavings

## Priority
High

## Value evidence
Item: `epic-durable-transcript-ownership-durable-event-log`. The release makes
extension-owned JSONL entries the transcript authority and promises live/reopen
equivalence across fork rehoming and the SDK's active compaction branch. Current
real-file coverage has one parent→fork edge and one uncomplicated mixed-era
prefix (`pi-extension/test/sdk-session-replacement.test.ts:364`, `:493`); raw
compaction reconciliation is synthetic (`pi-extension/src/session/transcript_projection.test.ts:530`, `:580`). No real file pins a multi-fork chain, a
compaction-heavy active branch, or execution/message/compaction producers
interleaved before reopen. Those are the data-loss boundaries of this feature,
not optional edge coverage.

## Gap type
bug-regression / e2e-seam / concurrent durable-file boundary

## Suggested test
```ts
// Use real SessionManager JSONL files and the production appendEntry adapter.
// 1. Build parent -> fork A -> fork B, diverge every branch, switch/reopen each,
//    and assert exact branch-local session_history with copied stable identities.
// 2. Compact more than once around durable user/assistant/tool/error/steering
//    facts; reopen and assert only the active branch survives, exactly once.
// 3. Gate producer callbacks explicitly, interleave message_end, tool hooks,
//    mesh/compaction appends on the real file, then reopen and compare the full
//    projected history to the live history byte-for-byte (apart from reply id).
```

## Test location (suggested)
`pi-extension/test/sdk-session-replacement.test.ts`
