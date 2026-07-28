---
id: feature-protocol-contract-discriminator-registry
kind: feature
stage: drafting
tags: [pi-extension, app, relay]
parent: null
depends_on: []
release_binding: null
gate_origin: refactor
created: 2026-07-28
updated: 2026-07-28
---

# Protocol-contract discriminator single-source-of-truth

## Brief
Five `gate-refactor` findings (scan library `protocol-contract`, rules
`handwritten-type-string` and `undocumented-protocol-island`) identify the same
divergence across three components: handwritten message/control discriminators
that duplicate the generated `relayControlTypes` / server-message registries,
plus one binary owner-channel format maintained by hand outside the schema IR.

- `gate-refactor-protocol-contract-relay-client-hello-auth-literals` —
  `pi-extension/src/transport/relay_client.ts:221` handwrites hello/auth
  discriminators already in the generated registry.
- `gate-refactor-protocol-contract-relay-transport-control-literals` —
  `pi-extension/src/extension/relay_transport.ts:560` handwrites
  `room_meta_update` and `subscribe_presence`.
- `gate-refactor-protocol-contract-session-projection-type-literals` —
  `pi-extension/src/session/sdk_session_projection.ts:515` handwrites
  `user_input`, `agent_message`, `session_history`, `queued_message_state`,
  `user_message`.
- `gate-refactor-protocol-contract-sync-user-input-handwritten` —
  `app/lib/data/sync/sync_service.dart:1030` hardcodes `user_input`,
  duplicating `generatedServerMessageTypes`.
- `gate-refactor-protocol-contract-owner-channel-binary-island` —
  `pi-extension/src/transport/secure_channel.ts:8` maintains the AEAD
  byte format by hand outside the schema IR with no documented rationale.

## Simplification opportunity
Collapse five handwritten discriminator sites onto keyed generated constants
(or, for the binary island, a canonical manifest/codegen source or a
documented "intentionally outside JSON Schema" rationale). Removing the
duplicates eliminates a class of future drift where a wire rename updates the
schema but not the hand-written call sites.

## Design notes
The scan libraries declare `findings-route: none` (fixes are not black-box-
preserving in all cases — the binary-island item may be a documentation-only
change), so this feature routes through normal feature/story design rather
than `refactor-design`. The design pass should:
1. Confirm where generated keyed discriminator constants live today
   (`protocol/generated/protocol.generated.ts` and the app/relay mirrors).
2. Decide whether to add a single `typeOfServerMessage(msg)`-style helper or
   keyed `MESSAGE_TYPES` constants, consumed by all five sites.
3. For the binary-island item, decide: document the intentional exclusion in
   the pattern's "When NOT to Use" + a canonical contract reference, OR add a
   binary-format manifest. The owner-channel AEAD format is genuinely outside
   JSON Schema; a documentation outcome is likely correct.
4. Coordinate with `gate-patterns-inconsistency-pair-request-flow-typed-decoder`
   (same `typed-wire-decoders` concern on the app pairing path) — that story
   is advancing independently but shares the generated-decoder direction.

## Children
- `gate-refactor-protocol-contract-relay-client-hello-auth-literals`
- `gate-refactor-protocol-contract-relay-transport-control-literals`
- `gate-refactor-protocol-contract-session-projection-type-literals`
- `gate-refactor-protocol-contract-sync-user-input-handwritten`
- `gate-refactor-protocol-contract-owner-channel-binary-island`
