---
kind: story
release_binding: v0.2.0
parent: feature-retire-legacy-piext-composition-seams
stage: done
id: gate-cruft-relay-owner-channel-bridge
tags: [cleanup]
depends_on: []
gate_origin: cruft
created: 2026-07-01
updated: 2026-07-20
---

# Retire temporary relay owner-channel bridge

## Confidence
Medium

## Category
compatibility shim

## Location
`pi-extension/src/extension/relay_transport.ts:57`

## Evidence
```ts
  /**
   * @internal Temporary owner-channel bridge while legacy call sites still need
   * direct access to the live RelayClient. Remove when owner ingress is fully
   * routed through RelayTransportPort.
   */
  currentRelayForOwnerChannels(): RelayClient | null;
```

## Removal
Finish routing owner ingress through `RelayTransportPort`/owner multiplexer APIs so `index.ts` no longer needs direct `RelayClient` access, then remove `currentRelayForOwnerChannels()` and its index call sites.

## Implementation

Moved owner-channel creation, presence subscription, and connection-generation
freshness behind `RelayTransportPort`; removed concrete relay inputs from the
owner multiplexer and the dead concrete-relay implementation from
`PairingCoordinator`. The coordinator now delegates relay start/status through
injected operations and exposes explicit keypair/self-revoke lifecycle methods.
Transport tests prove one listener per live relay, exact presence frames, and
freshness invalidation on replacement/close. Typecheck passed; focused
transport/owner tests passed 15/15 and critical extension ingress tests passed
17/17. The combined three-file run passed 204/205, with only the tracked
read-only cwd-lock flake failing.
