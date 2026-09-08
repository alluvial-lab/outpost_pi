---
id: gate-cruft-unused-legacy-fleet-arm-builder
gate_origin: cruft
created: 2026-09-08
updated: 2026-09-08
tags: [cleanup, pi-extension]
---

# Remove the unused legacy fleet arm request builder

## Confidence
Medium

## Category
dead function / compatibility shim

## Location
`pi-extension/src/extension/fleet_update.ts:69-71`

## Evidence
```ts
/** Build the legacy one-phase body for compatibility with old callers/tests. */
export function fleetArmRestartRequest(updateId: string): FleetArmRestartRequest {
  return { kind: FLEET_ARM_RESTART_KIND, update_id: updateId };
}
```

The current coordinator sends `fleetArmRestartPrepareRequest` and
`fleetArmRestartCommitRequest`. The current mesh adapter validates the legacy
kind only to classify it as `legacy`, and the sibling handler deliberately
returns `unsupported fleet arm phase`; no production or test call site imports
or invokes `fleetArmRestartRequest` (repository search finds only its
 declaration). The comment's claim that old callers/tests need this builder is
therefore unsubstantiated in the current tree.

## Removal
Delete `fleetArmRestartRequest` and its compatibility comment. Retain the
legacy discriminator and `legacy` phase handling in `isFleetArmRestartRequest`
and `fleetArmRestartPhase` if mixed-version peers must continue receiving a
bounded decline instead of waking the agent; this cleanup removes only the
unreferenced constructor and does not alter wire handling.
