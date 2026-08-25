---
id: epic-durable-transcript-ownership-retire-rederivation-two-source-boundary
kind: story
stage: done
tags: [pi-extension, refactor]
parent: epic-durable-transcript-ownership-retire-rederivation
depends_on: []
release_binding: v0.8.0
gate_origin: null
created: 2026-08-25
updated: 2026-08-25
---

# Bound transcript fallback to mixed-era reconciliation

Make current `message_end` user/assistant facts durable before transcript
visibility, leave tool authority with execution hooks, and confine permissive
SDK-message projection to the two-pass active-branch reconciler for old session
data. Delete transitional aggregate/runtime/test adapters that no longer have a
production caller.

## Acceptance criteria

- [x] Real-file durable-era reopen emits the same authoritative history as the
      live canonical events, even when SDK message fields could compete.
- [x] Real-file mixed-era reopen renders the SDK-only prefix and lets valid v1
      entries own matching/later facts.
- [x] Live SDK tool-call and tool-result messages do not create transcript facts;
      execution-hook durable entries remain authoritative.
- [x] No general fallback append method or direct SDK-message history mapper
      remains exported.
- [x] The two-source rule is documented verbatim at the reconciliation boundary.
- [x] Full pi-extension typecheck, test, and build pass.

## Risk and rollback

Medium risk: the refactor touches live user/assistant identity and persisted
compatibility. It is atomic because retiring the aliases before current facts
use durable recording would drop history. Revert this story commit as a unit;
the v1 persisted format and wire contract remain unchanged.

## Completion

- Execution capability: `sol/high` (host-side; cohesive cross-module refactor).
- Current SDK user and assistant-text facts now persist v1 entries before live
  transcript broadcast. SDK tool-call/toolResult messages create no transcript
  facts; execution hooks remain their sole durable producers.
- The pre-durable SDK mapper is private to
  `reconcileTranscriptContextEntries`; test SDK-message fixtures route through
  that same boundary.
- Deleted general fallback append/upgrade state, transitional aggregate aliases,
  the direct SDK-message history adapter, its production wrapper, and duplicated
  adapter-only tests. Retained the private two-pass fallback because real
  pre-upgrade JSONL sessions and corrupt/future custom-entry cases require it.
- Test-first evidence: the new live-boundary test initially failed because
  `recordSdkMessageTranscriptEvents` did not exist. Final focused reconciliation,
  aggregate, projection, and real-file reopen run passed 92 tests.
- Final verification: typecheck passed; all 59 test files passed (1079 passed,
  3 skipped); build passed.
