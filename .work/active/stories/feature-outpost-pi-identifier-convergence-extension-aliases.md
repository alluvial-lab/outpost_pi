---
id: feature-outpost-pi-identifier-convergence-extension-aliases
kind: story
stage: implementing
tags: [rebrand, pi-extension]
parent: feature-outpost-pi-identifier-convergence
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
---

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
