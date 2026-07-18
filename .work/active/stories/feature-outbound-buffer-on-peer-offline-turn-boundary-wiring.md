---
id: feature-outbound-buffer-on-peer-offline-turn-boundary-wiring
kind: story
stage: drafting
tags: [pi-extension, lifecycle]
parent: feature-outbound-buffer-on-peer-offline
depends_on: [feature-outbound-buffer-on-peer-offline-bounded-turn-buffer]
release_binding: null
gate_origin: null
created: 2026-07-18
updated: 2026-07-18
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

- [ ] `OwnerMultiplexerPort` and the composition adapter expose
      `completeOfflineTurn()`.
- [ ] Normal SDK turns and synthetic compaction turns seal the buffer through
      the existing `_applyTurnAndPublish({ type: "turn_end" })` path.
- [ ] The multiplexer does not introduce a second turn-state machine or a
      handwritten registry of terminal server-message variants.
- [ ] No protocol, relay, app, or persistence contract changes.
