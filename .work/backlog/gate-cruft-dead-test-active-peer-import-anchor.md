---
id: gate-cruft-dead-test-active-peer-import-anchor
gate_origin: cruft
created: 2026-08-28
updated: 2026-08-28
tags: [cleanup, pi-extension, testing]
---

# Remove the obsolete active-peer test import anchor

## Confidence
Medium

## Category
dead test scaffolding / stale comment

## Location
`pi-extension/src/extension.test.ts:1274-1278`

## Evidence
```ts
// Removed obsolete _state_isIdle helper — tests now check outpostPiTestHarness.state() or
// _hasActivePeerForTest directly. Kept the void below to anchor the new
// `_getActivePeerCountForTest` import so it isn't flagged as unused even
// when only some tests in this file consume it.
void _getActivePeerCountForTest;
```

The imported `_getActivePeerCountForTest` is already used by tests at lines
1404, 1427, and 4996. The standalone `void` expression and its stale
"anchor" explanation therefore add no coverage or retention guarantee.

## Removal
Delete the obsolete comment block and standalone `void _getActivePeerCountForTest;`
expression. Keep the import and its real assertions at the existing call sites.
