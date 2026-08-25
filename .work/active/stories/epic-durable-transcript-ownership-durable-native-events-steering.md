---
id: epic-durable-transcript-ownership-durable-native-events-steering
kind: story
stage: done
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

- [x] Test first proves accepted steering writes one v1 custom entry while
      ordinary app input remains outside this F3 checkpoint.
- [x] A fresh projection reopens steering identity/text/behavior and emits a
      replay `user_input` with `streaming_behavior: "steer"`.
- [x] Mixed-era SDK user fallback remains present while a later durable steer
      preserves its distinct identity and behavior.
- [x] `corepack pnpm typecheck && corepack pnpm test && corepack pnpm build`
      passes from `pi-extension/`.

## Completion

- Execution capability: `sol/high`.
- The reopen test failed first because durable `streamingBehavior` was decoded
  but omitted by the history mapper. Projection now carries it onto replayed
  `user_input` frames while legacy SDK users naturally omit it.
- Producer-connected steering coverage captures the accepted event through the
  real v1 append binding and proves its timestamp/text/identity/behavior equal
  the live echo. F2's concurrent producer migration owns the shared generic
  confirmation hook; this F3 checkpoint owns steering-specific preservation.
- Mixed-era coverage replays an SDK fallback user followed by a distinct
  durable steer without loss or duplication.
- Verification: typecheck passed; all 59 test files passed (1082 passed, 3
  skipped); build passed.
