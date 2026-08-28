---
id: gate-cruft-unused-relay-status-state
gate_origin: cruft
created: 2026-08-28
updated: 2026-08-28
tags: [cleanup, pi-extension]
---

# Remove unused relay status-change tracking

## Confidence
Medium

## Category
dead state / over-abstraction

## Location
`pi-extension/src/extension/relay_transport.ts:149-151,189-200`

## Evidence
```ts
let lastStatus: RelayConnectivity | null = null;
let lastStatusChangedAt = deps.now();

function status(): RelayConnectivity {
  void lastStatusChangedAt;
  if (!relayUrl) return setLastStatus("disconnected");
  return setLastStatus(relay ? "connected" : "reconnecting");
}
```

Repository-wide search finds no read of `lastStatusChangedAt`; the only
`deps.now()` calls initialize or assign this unobserved value. `lastStatus` and
`setLastStatus` likewise only maintain that unused timestamp and return the
input status. The timing seam is not part of the emitted snapshot or reconnect
schedule.

## Removal
Remove `lastStatus`, `lastStatusChangedAt`, `setLastStatus`, and the unused
`now()` dependency, then have `status()` return its existing disconnected,
connected, or reconnecting value directly. Update the adapter's composition and
test dependency objects. Preserve `lastEmittedStatus`, which still drives
relay-state deduplication.
