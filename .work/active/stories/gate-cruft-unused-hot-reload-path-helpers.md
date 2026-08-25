---
id: gate-cruft-unused-hot-reload-path-helpers
kind: story
stage: implementing
tags: [cleanup]
parent: null
depends_on: []
release_binding: v0.8.0
gate_origin: cruft
created: 2026-08-25
updated: 2026-08-25
---

# Remove unused hot-reload path helpers

## Confidence
High

## Category
Dead functions

## Relevance
Release-relevant: revealed by the strict unused-symbol scan of the changed extension entrypoint.

## Location
`pi-extension/src/index.ts:2847-2849, 2859-2861`

## Evidence
```ts
function _hotReloadEnabledPath(): string {
  return join(_outpostPiRemoteDir(), ".hot-reload-enabled");
}

function _runtimeIdentityPath(): string {
  return join(_outpostPiRemoteDir(), `.runtime-self-${process.pid}`);
}
```

`tsc --noUnusedLocals --noUnusedParameters` reports both functions as unused, and a repository-wide search finds no call sites. The active code uses literal `.hot-reload-enabled` and an inline runtime identity path, while the other path helpers are called by the lifecycle fence.

## Removal rationale
Delete both unreferenced helpers. Keep `_hotReloadArmedPath`, `_hotReloadClaimedPath`, and `_restartMarkerPath`, which have concrete callers; do not change the hot-reload file names or lifecycle behavior.

## Risk
None to runtime behavior. This is compiler-confirmed removal of two uncallable helpers with no persisted or wire contract impact.
