---
id: gate-cruft-codegen-unused-validator-helpers
kind: story
stage: done
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

## Implementation notes

- Execution capability: inline minimal cleanup; the codegen template and its tracked output are the sole affected boundary.
- Removed the unconditional `isStringWithMinLength` and `isFiniteNumberAtLeast` templates from `tools/protocol-codegen/src/index.ts`, then regenerated `pi-extension/src/protocol/generated/protocol.generated.ts`.
- Added a codegen regression assertion that the generated TypeScript contains neither unused helper; existing validator fixtures retain string and integer validation coverage.
- Confirmation: `npm run check` in `protocol/` passed; `corepack pnpm check:protocol` in `pi-extension/` confirmed the regenerated output is current.
- Bounded inline review: diff is limited to the two dead helper templates, their generated copies, and the focused generation assertion; no validation expressions changed.
