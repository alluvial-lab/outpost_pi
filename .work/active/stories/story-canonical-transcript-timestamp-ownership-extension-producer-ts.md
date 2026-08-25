---
id: story-canonical-transcript-timestamp-ownership-extension-producer-ts
kind: story
stage: implementing
tags: [pi-extension, bug]
parent: feature-canonical-transcript-timestamp-ownership
depends_on: [epic-durable-transcript-ownership-durable-event-log]
release_binding: null
gate_origin: null
created: 2026-08-03
updated: 2026-08-25
---

# Extension producer-ts coverage (agent_done, user_message echoes, mesh cards)

Unit B of `feature-canonical-transcript-timestamp-ownership`. Stamp a server
`ts` on the authoritative producers that still omit it (Q2 decision = a:
mesh cards are authoritative).

## Change (`pi-extension/src/index.ts`)

- `agent_end` → `agent_done` broadcast: include the terminal `ts` (the handler
  already computes it).
- Initial + dedupe `user_message` echoes (`_confirmUserDelivery` /
  `_attemptUserDelivery` delivered-id dedupe): reuse the existing recorded `ts`
  (Unit A's `recordedTsFor` lookup) instead of emitting ts-less frames.
- `_deliverMeshMessageToAgent` (Q2=a): stamp a server `ts` on the
  `tool="agent-network"` `tool_request`/`tool_result` pair.

## Acceptance

- [ ] `agent_done`, `user_message` initial/dedupe echoes, and
  `tool="agent-network"` frames carry a server `ts` equal to their history/owner
  `ts` (producer-connected extension tests — assert live == history, not
  injected values).

## Ordering

`depends_on: [epic-durable-transcript-ownership-durable-event-log]`
(needs F1's durable codec/log, recorded-ts lookup, and single-owner model).
Parallel with C; unblocks D.
