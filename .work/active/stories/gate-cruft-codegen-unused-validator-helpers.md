---
id: gate-cruft-codegen-unused-validator-helpers
kind: story
stage: implementing
tags: [cleanup]
parent: null
depends_on: []
release_binding: v0.2.0
gate_origin: cruft
created: 2026-07-20
updated: 2026-07-20
---

# Stop generating unused protocol validator helpers

## Confidence
High

## Category
dead generated functions

## Location
`pi-extension/src/protocol/generated/protocol.generated.ts:813`

## Evidence
```ts
function isStringWithMinLength(value: unknown, minLength: number): value is string {
  return typeof value === "string" && value.length >= minLength;
}

function isFiniteNumberAtLeast(value: unknown, minimum: number): value is number {
  return isFiniteNumber(value) && value >= minimum;
}
```

`tsc --noUnusedLocals --noUnusedParameters --noEmit` reports both helpers as unused. The generator in `tools/protocol-codegen/src/index.ts:929` emits them unconditionally, while its string validation generation in `tools/protocol-codegen/src/index.ts:408` inlines `minLength` checks and no current schema produces a `number` validator using `isFiniteNumberAtLeast`.

## Removal
Remove the unused helper templates from `emitValidatorHelpers` (or emit helpers only when generated expressions reference them), regenerate `protocol.generated.ts`, and preserve the existing integer and string validation behavior.
