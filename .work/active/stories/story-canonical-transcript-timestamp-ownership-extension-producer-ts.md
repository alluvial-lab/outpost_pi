---
id: story-canonical-transcript-timestamp-ownership-extension-producer-ts
kind: story
stage: done
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

## F1 reconciliation (2026-08-25)

- The pre-F1 design's per-kind `recordedTsFor`/Unit A mechanics were replaced by
  F1's generic `recordDurableTranscriptEvent` + `recordedTranscriptTs` API and
  persistence-before-visibility result contract.
- Live SDK `message_end` can install a compatibility fallback before the later
  tool/delivery hook fires. `TranscriptEventLog` now tracks those fallback
  identities so the authoritative durable hook record can persist and replace
  that one in-memory fact; already-durable identities remain ordinary no-op
  duplicates.
- App-origin `message_end` echoes reuse the delivery hook's recorded timestamp.
  In the unusual async ordering where SDK persistence arrives before delivery
  settles, its fallback stays available for replay but its non-authoritative SDK
  timestamp is not broadcast; the delivery hook upgrades and emits the sole
  canonical echo.
- Mesh cards are recorded as the authoritative durable request/result pair here
  because F2 explicitly classifies those app-visible cards as timestamp-owned
  transcript facts; this supersedes the pre-F1 file-location sketch.

## Acceptance

- [ ] `agent_done`, `user_message` initial/dedupe echoes, and
  `tool="agent-network"` frames carry a server `ts` equal to their history/owner
  `ts` (producer-connected extension tests — assert live == history, not
  injected values).

## Ordering

`depends_on: [epic-durable-transcript-ownership-durable-event-log]`
(needs F1's durable codec/log, recorded-ts lookup, and single-owner model).
Parallel with C; unblocks D.

## Implementation

- Execution capability: `sol/high`.
- Migrated tool request/result hooks, app-origin user confirmations, terminal
  `assistant_done`, and agent-network cards onto F1 durable recording. Each
  producer captures one hook-lifecycle timestamp, persists it, and reuses the
  recorded value for every live owner frame and duplicate echo.
- Added compatibility-safe fallback upgrading and mixed-era reopen coverage;
  SDK-derived fallback remains available when no durable writer exists.
- Added a producer provenance matrix across tool hooks, initial/deduplicated
  user echoes, `agent_done`, and mesh cards, including durable custom-entry and
  live/history equality assertions.
- Verification: focused 300-test transcript/extension matrix passed; full
  pi-extension `typecheck`, 59-file test suite (1079 passed, 3 skipped), and
  build passed.
