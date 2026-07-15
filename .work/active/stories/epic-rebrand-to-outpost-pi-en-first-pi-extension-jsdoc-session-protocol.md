---
id: epic-rebrand-to-outpost-pi-en-first-pi-extension-jsdoc-session-protocol
kind: story
stage: review
tags: [rebrand, docs, pi-extension]
parent: epic-rebrand-to-outpost-pi-en-first-pi-extension
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
---

# Add JSDoc to session, mesh, pairing, protocol, and transport services

Add English `/** */` comments only to the Always-tier gaps. Preserve current
wire contracts and code behavior. Generated protocol declarations, tests,
constants, and DTO-only schemas remain Skip-tier.

## Gap-fill inventory

- `src/mesh/self_revoke.ts`: `SelfRevokeOptions`, `SelfRevoke`.
- `src/pairing/crypto.ts`: `Ed25519Keypair`, `ed25519Sign`, `ed25519Verify`.
- `src/pairing/qr.ts`: `qrSession`, `buildQRUri` (not the TTL constant).
- `src/pairing/storage.ts`: `listPeers`, `addPeer`, `removePeer`; `PeerRecord`
  is a storage DTO and stays Skip-tier.
- `src/protocol/codec.ts`: `DecodeError`, `encodeClient`, `decodeServer`,
  `decodeClient` including invalid/unsupported error behavior.
- `src/protocol/session_scope.ts`: `RemoteSessionId`, the three exported
  `is*Type` predicates, and any missing canonical-registry contract comments;
  generated schema types and self-evident registries remain Skip-tier.
- `src/reachability/contract.ts`: `ReachabilityState`, `reachabilityBackoffMs`,
  `ReachabilityTransition`, and `ReachabilityEvent`; document the canonical
  state-machine contract rather than table contents.
- `src/session/bridge.ts`: `CrossPcBridge`, `attachCrossPcBridge`.
- `src/session/broker.ts`: `Broker` public lifecycle/routing contract.
- `src/session/envelope.ts`: `EnvelopeError`, `serialize`, `parse`.
- `src/session/leader_election.ts`: `ElectionResult` discriminated result.
- `src/session/local_config.ts`: `loadLocalConfig`, `saveLocalConfig` (not the
  config DTO).
- `src/session/mesh_node.ts`: `MeshNode` public lifecycle contract.
- `src/session/peer.ts`: `ReconnectHandler`, `SessionPeerOptions`, `AckStatus`,
  `AckResult`, `SessionPeer`.
- `src/session/remote_session.ts`: `RemoteSession`, `uuid7`,
  `resolveRemoteSessionId`, `RemoteSessionIssuer`.
- `src/session/sdk_session_projection.ts`: `AgentMessageApi`, `FreshActionApi`,
  `SessionHistorySnapshot`, `SdkSessionProjectionOutputs`, `SeededUserTurn`,
  `SdkSessionProjectionOptions`, `isAgentMessageApi`, `SdkSessionProjection`.
- `src/session/session_gate.ts`: `SessionGateResult`, `validateClientSession`.
- `src/session/transcript_event.ts`: `TranscriptEvent`, `TranscriptTurnStatus`,
  `TranscriptTurnView`, `TranscriptProjection`.
- `src/session/transcript_projection.ts`: `LegacyAgentMessage`,
  `SessionHistoryProjection`, and the exported projection/mapping helpers.
- `src/session/turn_state.ts`: exported state/event/projection types plus
  `initialTurnSnapshot`, `reduceTurn`, and `projectTurn`.
- `src/session/wizard.ts`: `joinWizard`.
- `src/transport/pi_forward_client.ts`: `PiForwardClient`; inspect relay-client
  event contracts and add only genuinely missing Always-tier service docs.

## Acceptance criteria

- [x] Contract-bearing exports above have English JSDoc, including throw/result
  semantics and lifecycle ownership where the code exposes them.
- [x] No JSDoc is added to generated protocol output, test files, or DTO-only
  wire/storage shapes.
- [x] No relay, mesh, session, or protocol runtime behavior changes.
- [x] Focused protocol/session/transport tests and final feature verification pass.

## Implementation notes
- Files changed: `pi-extension/src/mesh/self_revoke.ts`, `pi-extension/src/pairing/{crypto,qr,storage}.ts`, `pi-extension/src/protocol/{codec,session_scope}.ts`, `pi-extension/src/reachability/contract.ts`, `pi-extension/src/session/{bridge,broker,envelope,leader_election,local_config,mesh_node,peer,remote_session,sdk_session_projection,session_gate,transcript_event,transcript_projection,turn_state,wizard}.ts`, and `pi-extension/src/transport/pi_forward_client.ts`.
- Tests added: none; this documentation-only change preserves existing contracts and behavior.
- Verification: `COREPACK_HOME=/tmp/corepack-home corepack pnpm typecheck`, `test` (51 files, 837 passed, 3 skipped), and `build` passed from `pi-extension/`.
- Discrepancies from design: none. `relay_client.ts` and `peer_channel.ts` were audited; their relay/event lifecycle contracts were already documented, so no non-inventory JSDoc was added.
- Adjacent issues parked: none.
