---
id: epic-durable-transcript-ownership-durable-native-events-steering
kind: story
stage: implementing
tags: [pi-extension]
parent: epic-durable-transcript-ownership-durable-native-events
depends_on: [epic-durable-transcript-ownership-durable-native-events-compaction]
release_binding: null
gate_origin: null
created: 2026-08-25
updated: 2026-08-25
---

# Persist steering events

Record accepted app steering as a durable `user_confirmed` event carrying
`streamingBehavior: "steer"`, without taking ownership of ordinary user-message
timestamp migration assigned to sibling F2. Project the behavior back onto
`session_history` so reopen is equivalent to the accepted live echo.

## Acceptance evidence

- [ ] Test first proves accepted steering writes one v1 custom entry while
      ordinary app input remains outside this F3 checkpoint.
- [ ] A fresh projection reopens steering identity/text/behavior and emits a
      replay `user_input` with `streaming_behavior: "steer"`.
- [ ] Mixed-era SDK user fallback remains present while a later durable steer
      preserves its distinct identity and behavior.
- [ ] `corepack pnpm typecheck && corepack pnpm test && corepack pnpm build`
      passes from `pi-extension/`.
