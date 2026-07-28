---
id: gate-refactor-lifecycle-self-revoke-discards-async-detach
kind: story
stage: implementing
tags: [pi-extension]
parent: feature-lifecycle-disposal-async-void
depends_on: [gate-refactor-lifecycle-bye-frames-race-relay-shutdown]
release_binding: null
gate_origin: refactor
created: 2026-07-24
updated: 2026-07-28
---

# Self-revoke discards asynchronous owner-channel teardown

## Source
gate-refactor scan for v0.3.0 (2026-07-24) — library `lifecycle`, rule `unguarded-async-void`, confidence Medium → parked per gate_finding_routing / ambient rule.

## Location
`pi-extension/src/extension/command_surface/pairing_coordinator.ts:213`

## Issue
The onRevoke callback discards the Promise returned by owners.detach, even though SelfRevoke supports and awaits asynchronous callbacks.

## Fix
Make onRevoke async and await owners.detach(ownerEpk, "session_replaced") before completing the callback.

## Design checkpoint
In `pi-extension/src/extension/command_surface/pairing_coordinator.ts`:

```ts
onRevoke: async (ownerEpk: string): Promise<void> => {
  this.deps.refreshPairingsCache();
  if (this.deps.ownerHas(ownerEpk)) {
    await this.deps.owners.detach(ownerEpk, "session_replaced");
  }
  // existing local revoke notice follows
};
```

Reuse `OwnerMultiplexerPort.detach`; do not add another helper or a nested `void` observer. Preserve the fresh injected capability posture from `ea074e0` and do not capture a command UI context across the await.

## Acceptance evidence
- With `owners.detach` held by a deferred barrier, `SelfRevoke.checkOnce()` and the local revoke notice remain pending until release.
- The owner receives `session_replaced` exactly once.
- A detach rejection travels through the awaited self-revoke chain and never becomes unhandled.

## Ordering
Depends on `gate-refactor-lifecycle-bye-frames-race-relay-shutdown`, which establishes and verifies the shared awaited detach/drain contract.
