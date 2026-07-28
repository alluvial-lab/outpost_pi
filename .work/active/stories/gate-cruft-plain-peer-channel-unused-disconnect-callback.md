---
id: gate-cruft-plain-peer-channel-unused-disconnect-callback
kind: story
stage: done
tags: [cleanup, pi-extension]
parent: null
depends_on: []
release_binding: null
gate_origin: cruft
created: 2026-07-24
updated: 2026-07-28
---

# Plain peer channel retains a suppressed, unused disconnect callback

## Source
gate-cruft scan for v0.3.0 (2026-07-24). Medium confidence, ambient-adjacent
(release-relevant but medium → parked per gate_finding_routing).

## Confidence
Medium (pattern-matched)

## Category
compatibility shim

## Location
`pi-extension/src/transport/peer_channel.ts:44`

## Evidence
```ts
constructor(
  private readonly relay: RelayClient,
  private readonly remotePeerId: string,
  private readonly onMessage: (msg: ClientMessage) => void,
  _onDisconnect?: () => void,
) {
  this._unsubscribe = subscribeRelayIngress(relay, (ingress) => this._onIngress(ingress));
  void _onDisconnect;
}
```
The sole production caller supplies the callback at
`extension/relay_transport.ts:623`, but `PlainPeerChannel` never invokes it.

## Removal
Remove `_onDisconnect` from `PlainPeerChannel` and the unused callback
allocation at its production call site.

## Implementation notes

- Removed the unused constructor callback and its production allocation.
- Changed `pi-extension/src/transport/peer_channel.ts` and
  `pi-extension/src/extension/relay_transport.ts`.
- Verified with `vitest run src/session/broker_remote.test.ts` (41 tests) and
  `tsc --noEmit`.
