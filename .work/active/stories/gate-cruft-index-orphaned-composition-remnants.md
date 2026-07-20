---
id: gate-cruft-index-orphaned-composition-remnants
kind: story
stage: implementing
tags: [pi-extension, cleanup]
parent: null
depends_on: []
release_binding: extension-0.2.0
gate_origin: cruft
created: 2026-07-20
updated: 2026-07-20
---

# Remove orphaned index composition remnants

## Severity
High

## Confidence
High (tool-detected)

## Category
unused import / dead function

## Location
`pi-extension/src/index.ts:118`, `pi-extension/src/index.ts:125`, `pi-extension/src/index.ts:1144`

## Evidence
```text
src/index.ts(118,3): error TS6133: 'sessionAuditPath' is declared but its value is never read.
src/index.ts(125,3): error TS6133: 'effectiveAutoStartRelay' is declared but its value is never read.
src/index.ts(1144,10): error TS6133: '_currentPairingSessionSnapshot' is declared but its value is never read.
```

`./node_modules/.bin/tsc --noUnusedLocals --noUnusedParameters --noEmit` reported all three diagnostics. Repository search found no caller for `_currentPairingSessionSnapshot`; the function became orphaned when the legacy pairing-coordinator seam was retired.

## Removal
Remove the two unused `index.ts` imports and `_currentPairingSessionSnapshot`; retain the live `sessionAuditPath` and `effectiveAutoStartRelay` imports in `extension/command_surface/local_mesh_commands.ts`, where they remain used.

## Gate note
The cruft scan was run inline because the requested gate path disallowed a nested scanner agent; isolation is reduced.
