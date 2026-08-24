---
id: gate-cruft-upload-single-slot-limit
kind: story
stage: done
tags: [cleanup]
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: cruft
created: 2026-08-24
updated: 2026-08-25
---

# Remove the numeric max-inflight abstraction from the single-slot capture upload

## Confidence
High

## Category
over-abstraction; unused generated protocol field

## Location
- `pi-extension/src/actions/capture_upload_handler.ts:128-130`
- `tools/protocol-codegen/bin/protocol-codegen.mjs:745-755`
- `app/lib/protocol/generated/protocol.g.dart:5-7`

## Finding
The upload handler owns one nullable `active` slot, but converts that boolean to
`0|1` and compares it with a generated `CAPTURE_UPLOAD_MAX_INFLIGHT` value that is
fixed at `1`. The same schema metadata also emits `captureUploadMaxInflight` into
the Dart projection, where whole-repo search finds no consumer. The TS constant is
used only by this pseudo-generalized boolean check; no implementation supports a
per-session or multi-upload collection.

## Evidence
```ts
const activeCount = this.active ? 1 : 0;
if (activeCount >= CAPTURE_UPLOAD_MAX_INFLIGHT) {
  this.fail(sender, message, "busy", "Another capture upload is already in progress.");
  return;
}
```

```dart
const int captureUploadMaxInflight = 1;
```

## Removal rationale
Keep the current single-upload behavior explicit with `if (this.active !== null)`
and remove `maxInflightPerSession` from the protocol-codegen metadata and generated
projections. Regenerate the checked-in protocol files; retain the chunk and total-byte
limits, which are independently enforced and consumed.

## Risk
No current behavior changes. A future multi-upload design would need to reintroduce
an explicit per-session capacity and state collection rather than reviving this
unused numeric projection.

## Implementation
- Execution capability: `sol/high` (bundled with the shared capture-upload hardening boundary).
- Replaced the numeric `0|1` comparison with the handler's explicit nullable-slot check.
- Removed `maxInflightPerSession` from schema metadata, TypeScript IR/emission, Dart emission, the committed Dart IR fixture, and regenerated TS/Dart projections.
- Updated codegen contract tests for the capture message family while preserving the single-upload admission regression test.
- Verification: capture-upload suite 15/15 pass; protocol schema/codegen suite 7/7 pass; repository grep finds no remaining runtime/generated max-inflight symbol.
- Adjacent issues parked: none.
