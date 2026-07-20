---
id: feature-outbound-buffer-on-peer-offline-turn-boundary-wiring
kind: story
stage: done
tags: [pi-extension, lifecycle]
parent: feature-outbound-buffer-on-peer-offline
depends_on: [feature-outbound-buffer-on-peer-offline-bounded-turn-buffer]
release_binding: extension-0.2.0
gate_origin: null
created: 2026-07-18
updated: 2026-07-20
---

# Wire canonical turn boundaries into outbound buffering

## Brief

Implement Unit 3 from `feature-outbound-buffer-on-peer-offline`: expose the
multiplexer boundary operation through the owner port and drive it from the
existing canonical `TurnEvent.type == "turn_end"` path rather than inferring
turns from duplicated `ServerMessage.type` lists.

## Files

- `pi-extension/src/extension/ports.ts`
- `pi-extension/src/index.ts`

## Acceptance criteria

- [x] `OwnerMultiplexerPort` and the composition adapter expose
      `completeOfflineTurn()`.
- [x] Normal SDK turns and synthetic compaction turns seal the buffer through
      the existing `_applyTurnAndPublish({ type: "turn_end" })` path.
- [x] The multiplexer does not introduce a second turn-state machine or a
      handwritten registry of terminal server-message variants.
- [x] No protocol, relay, app, or persistence contract changes.

## Implementation

Added `completeOfflineTurn()` to the owner port and composition adapter. The
existing `_applyTurnAndPublish` helper now seals offline intervals only for its
canonical `TurnEvent.type === "turn_end"` branch, so both SDK turn completion
and synthetic compaction completion share the reducer-owned boundary without
re-enumerating server-message variants.

Verification: `./node_modules/.bin/tsc --noEmit`; focused SDK `turn_end`
working-convergence Vitest.
