---
id: gate-cruft-generated-validator-unused-number-helper
kind: story
stage: implementing
tags: [cleanup]
parent: null
depends_on: []
release_binding: v0.3.0
gate_origin: cruft
created: 2026-07-24
updated: 2026-07-24
---

# Generated protocol validator includes an unused number helper

## Confidence
High (tool-detected: `tsc --noUnusedLocals --noUnusedParameters --noEmit` TS6133)

## Category
dead function

## Location
`pi-extension/src/protocol/generated/protocol.generated.ts:827`

## Evidence
```ts
function isFiniteNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}
```
No bundled protocol schema declares `type: "number"`, and
`tools/protocol-codegen/src/index.ts:938` emits the helper unconditionally.

## Removal
Stop emitting `isFiniteNumber` from the codegen when no generated validator
references it (emit conditionally), then regenerate `protocol.generated.ts`.
Preserve conditional emission so a future schema with a number validator
regenerates it. Generated file — fix the generator, not the output.
