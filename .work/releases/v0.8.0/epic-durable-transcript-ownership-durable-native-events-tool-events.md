---
id: epic-durable-transcript-ownership-durable-native-events-tool-events
kind: story
stage: done
tags: [pi-extension]
parent: epic-durable-transcript-ownership-durable-native-events
depends_on: []
release_binding: v0.8.0
gate_origin: null
created: 2026-08-25
updated: 2026-08-25
---

# Persist native tool request/result events

Migrate execution-hook tool requests/results and app-facing `agent-network` mesh
cards from the transitional in-memory append path to F1's durable recorder.
Request and result remain separate canonical facts, including the immediate mesh
pair. Persistence failure is fail-closed for transcript visibility; mesh ingress
still reaches the SDK even if its app card cannot become authoritative.

## Acceptance evidence

- [x] Tests first prove ordinary and mesh request/result producers append v1
      custom entries before live visibility.
- [x] A fresh projection reopens both distinct facts and projects the same
      `tool_request`/`tool_result` history as the live producer.
- [x] Mixed-era history retains SDK fallback tool facts while later durable
      native facts win matching collisions; pre-upgrade mesh cards are not
      invented.
- [x] `corepack pnpm typecheck && corepack pnpm test && corepack pnpm build`
      passes from `pi-extension/`.

## Completion

- Execution capability: `sol/high`.
- Producer-connected tests failed first with no v1 entries, then passed after
  execution hooks and admitted mesh cards used F1's durable recorder.
- Reopen coverage proves one legacy SDK request plus the later durable mesh
  request/result pair projects in order with no invented pre-upgrade mesh card.
- Concurrent F2 producer work touched the same native sites and committed the
  shared implementation/test hunks in `27b67210`; that commit's verification
  reports typecheck, all 59 test files (1079 passed, 3 skipped), and build green.
  This checkpoint records F3 ownership without rewriting shared history.
