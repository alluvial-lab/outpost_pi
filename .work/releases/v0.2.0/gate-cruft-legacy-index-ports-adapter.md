---
kind: story
release_binding: v0.2.0
parent: feature-retire-legacy-piext-composition-seams
stage: done
id: gate-cruft-legacy-index-ports-adapter
tags: [cleanup]
depends_on: []
gate_origin: cruft
created: 2026-07-01
updated: 2026-07-20
---

# Retire or neutralize the legacy index ports adapter after module extraction

## Confidence
Medium

## Category
compatibility shim

## Location
`pi-extension/src/extension/legacy_ports.ts:66`

## Evidence
```ts
export interface LegacyIndexDeps {
  relay: LegacyRelayTransportDeps;
  owners: LegacyOwnerMultiplexerDeps;
  session: LegacySdkSessionProjectionDeps;
  commands: LegacyCommandSurfaceDeps;
}

export function createLegacyIndexPorts(deps: LegacyIndexDeps): RemotePiRuntimePorts {
  return {
    relay: createLegacyRelayTransport(deps.relay),
    owners: createLegacyOwnerMultiplexer(deps.owners),
    session: createLegacySdkSessionProjection(deps.session),
    commands: createLegacyCommandSurface(deps.commands),
  };
}
```

`pi-extension/src/index.ts:88` imports `createLegacyIndexPorts`, and `pi-extension/src/index.ts:1131` still constructs `legacyPorts` for the default extension factory after the extraction arc.

## Removal
Once the split modules are the canonical runtime wiring, either remove this compatibility adapter and construct `RemotePiRuntimePorts` directly at the composition root, or rename the adapter/types away from `Legacy*` if they are no longer transitional. Keep the cleanup surgical: update imports/usages and delete only the now-obsolete shim names/wrappers.

## Implementation

Replaced `createLegacyIndexPorts(createIndexDeps())` with a direct
`createRuntimePorts(): OutpostPiRuntimePorts` graph, renamed the runtime and
command-surface composition symbols, removed the unused session `setRoomId`
port member, and deleted `legacy_ports.ts`. Typecheck and build passed;
composition-root tests passed 4/4. The combined extension run passed 193/194,
with only the tracked read-only cwd-lock flake failing.
