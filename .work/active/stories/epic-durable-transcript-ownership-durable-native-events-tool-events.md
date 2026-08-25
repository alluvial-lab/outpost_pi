---
id: epic-durable-transcript-ownership-durable-native-events-tool-events
kind: story
stage: implementing
tags: [pi-extension]
parent: epic-durable-transcript-ownership-durable-native-events
depends_on: []
release_binding: null
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

- [ ] Tests first prove ordinary and mesh request/result producers append v1
      custom entries before live visibility.
- [ ] A fresh projection reopens both distinct facts and projects the same
      `tool_request`/`tool_result` history as the live producer.
- [ ] Mixed-era history retains SDK fallback tool facts while later durable
      native facts win matching collisions; pre-upgrade mesh cards are not
      invented.
- [ ] `corepack pnpm typecheck && corepack pnpm test && corepack pnpm build`
      passes from `pi-extension/`.
