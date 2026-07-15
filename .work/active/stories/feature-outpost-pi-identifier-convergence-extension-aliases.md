---
id: feature-outpost-pi-identifier-convergence-extension-aliases
kind: story
stage: review
tags: [rebrand, pi-extension]
parent: feature-outpost-pi-identifier-convergence
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
---

## Implementation notes

- Renamed the extension's internal `remotePi` path and test-harness identifiers to `outpostPi` across the specified implementation and test surfaces.
- Also renamed the standalone CLI help-text helper so `rg 'remotePi|__remotePi' pi-extension/src/` is clean.
- Verification passed: `corepack pnpm typecheck` and `corepack pnpm test` (51 files, 837 passed, 3 skipped).

# Rename extension remotePi aliases and test-harness exports

Implements Unit 3 of `feature-outpost-pi-identifier-convergence`.

## Scope

Rename internal identifiers with no wire/compatibility meaning:

- `pi-extension/src/daemon/install.ts`: `remotePi` param → `outpostPi` (both the POSIX `installOutpostPi` path and the Windows variant); update the local variable and error messages.
- `pi-extension/src/daemon/install.test.ts`: `fakePaths.remotePi` → `fakePaths.outpostPi`.
- `pi-extension/src/extension/composition_root.ts:56`: `__remotePiTestHarness` → `__outpostPiTestHarness`.
- `pi-extension/src/extension.test.ts`: `remotePiTestHarness` → `outpostPiTestHarness`, `__remotePiTestHarness` → `__outpostPiTestHarness`.
- `pi-extension/src/index.ts`: `remotePiTestHarness` re-export → `outpostPiTestHarness`; `_connectForTest`/`_stopForTest`/`_getState`/`routeClientMessage` bindings.

## Verification

```bash
cd pi-extension
export PNPM_HOME=/home/agent/projects/remote_pi/.pnpm-store npm_config_cache=/home/agent/projects/remote_pi/.npm-cache XDG_CACHE_HOME=/home/agent/projects/remote_pi/.xdg-cache
corepack pnpm typecheck && corepack pnpm test
```

`rg 'remotePi|__remotePi' pi-extension/src/` must return no hits.
