---
id: epic-durable-transcript-ownership-durable-native-events-compaction
kind: story
stage: implementing
tags: [pi-extension]
parent: epic-durable-transcript-ownership-durable-native-events
depends_on: [epic-durable-transcript-ownership-durable-native-events-tool-events]
release_binding: null
gate_origin: null
created: 2026-08-25
updated: 2026-08-25
---

# Persist compaction markers

Record `session_compact` markers through F1's durable v1 append path, using the
SDK compaction entry timestamp when valid so the raw SDK mixed-era fallback and
the durable fact share one stable identity. Working-state convergence remains
independent of persistence success.

## Acceptance evidence

- [ ] Test first proves the compaction hook writes a v1 custom entry before its
      live marker and uses the same event for replay.
- [ ] A fresh projection reopens the marker with summary, token count, and
      canonical timestamp intact.
- [ ] Mixed-era raw SDK compactions remain replayable and a matching durable
      marker suppresses duplicate fallback.
- [ ] `corepack pnpm typecheck && corepack pnpm test && corepack pnpm build`
      passes from `pi-extension/`.
