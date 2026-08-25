---
id: epic-durable-transcript-ownership-retire-rederivation-two-source-boundary
kind: story
stage: implementing
tags: [pi-extension, refactor]
parent: epic-durable-transcript-ownership-retire-rederivation
depends_on: []
release_binding: null
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

- [ ] Real-file durable-era reopen emits the same authoritative history as the
      live canonical events, even when SDK message fields could compete.
- [ ] Real-file mixed-era reopen renders the SDK-only prefix and lets valid v1
      entries own matching/later facts.
- [ ] Live SDK tool-call and tool-result messages do not create transcript facts;
      execution-hook durable entries remain authoritative.
- [ ] No general fallback append method or direct SDK-message history mapper
      remains exported.
- [ ] The two-source rule is documented verbatim at the reconciliation boundary.
- [ ] Full pi-extension typecheck, test, and build pass.

## Risk and rollback

Medium risk: the refactor touches live user/assistant identity and persisted
compatibility. It is atomic because retiring the aliases before current facts
use durable recording would drop history. Revert this story commit as a unit;
the v1 persisted format and wire contract remain unchanged.
