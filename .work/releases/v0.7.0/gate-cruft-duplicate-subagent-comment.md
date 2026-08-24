---
id: gate-cruft-duplicate-subagent-comment
kind: story
stage: done
tags: [cleanup]
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: cruft
created: 2026-08-24
updated: 2026-08-24
---

# Remove the superseded subagent message-end comment

## Confidence
High

## Category
stale comment

## Location
`pi-extension/src/index.ts:1447-1463`

## Finding
The `message_end` handler contains two adjacent explanations of the same
subagent-leak gate. The first says only assistant messages are suppressed; the
second, newer block and the executable predicate correctly suppress both
assistant and user messages. The first block is a leftover from before the
dispatch-prompt leak was fixed and contradicts the current behavior.

## Evidence
```ts
// Suppress recording/broadcast for assistant messages so they
// neither reach the phone live ...
// Subagent-leak gate: while a `subagent` tool execution is open, the
// child session's `message_end` fires for the subagent's messages.
// Suppress recording/broadcast for BOTH `assistant` ... AND
// `user` ...
const suppressForSubagent =
  (m.role === "assistant" || m.role === "user") && subagentGate.isActive();
```

## Removal rationale
Delete the obsolete assistant-only paragraph at lines 1447-1451 and retain one
concise comment that matches the two-role predicate and explains why tool results
still pass through. No executable code change is required.

## Risk
None to runtime behavior. The retained comment remains the single explanation of
the existing suppression contract.

## Implementation

- Removed the superseded assistant-only paragraph and kept one concise comment
  describing suppression of both assistant and dispatch-prompt user messages,
  while documenting why `toolResult` still passes through.
- Runtime code was unchanged.

## Verification

- Comment-only change; no additional runtime test was required.
