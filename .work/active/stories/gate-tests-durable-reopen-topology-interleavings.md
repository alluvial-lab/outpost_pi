---
id: gate-tests-durable-reopen-topology-interleavings
kind: story
stage: done
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

## Implementation

Added three production-boundary tests over real `SessionManager` JSONL files:

- a parent → fork A → fork B topology that diverges each branch, resumes every
  file, and proves copied durable identities are rehomed exactly once without
  leaking child facts into ancestors;
- two compactions around durable user/tool/compaction/assistant/error facts,
  using the SDK compaction timestamps, then reopening to prove only the latest
  active branch survives and the SDK/durable compaction pair collapses once;
- explicit started/release gates for actual `message_end`, tool start/end,
  agent-network mesh-card, and `session_compact` producers. The selected
  interleaving is appended through the production SDK context, synchronized
  live, reopened from disk, and compared as byte-identical event JSON (the
  request reply id is intentionally outside the event comparison).

No product defect was found. Early red runs identified two fixture mistakes,
not product behavior: `SessionManager` does not create its JSONL until an
assistant message flushes it, and compaction fallback authority collides on the
real SDK compaction timestamp. The final tests model both production rules.

Verification:

- `corepack pnpm exec vitest run test/sdk-session-replacement.test.ts` (12 passed)
