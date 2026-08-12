---
id: story-v040-refresh-dist-marker-mode
kind: story
stage: done
tags: [pi-extension, lifecycle]
parent: null
depends_on: []
release_binding: v0.4.0
gate_origin: null
created: 2026-08-11
updated: 2026-08-11
---

# refresh-dist.sh creates markers the hardened wrapper rejects

## Origin
Phase 8 completion review (v0.4.0) — material blocker INTRODUCED by gate-refactor-restart-marker-cross-process-race. That fix hardened the wrapper to require exactly 0600 markers, but refresh-dist.sh (the documented multi-agent dist refresh) still creates them at 0666 & umask (0644/0664). refresh-dist will terminate each Pi, the wrapper rejects its marker, and the wrapper stops instead of relaunching — breaking the mobile-managed deploy.

## Location
scripts/refresh-dist.sh:101-103 (Python open(...,"w")); wrapper requirement scripts/pi-restart-loop.sh:41-47,93-98; test pi-extension/src/pi_restart_loop.test.ts:114-116 masks it via umask 077.

## Work
Create the marker owner-only (0600) — os.open(..., O_WRONLY|O_CREAT|O_TRUNC, 0o600) or open + os.chmod. Add coverage for the real producer contract (a default-umask producer must yield an accepted marker); remove the test's umask-077 crutch so the integration is actually exercised.

## Implementation notes

- Execution capability: direct inline repair; the defect was confined to one producer and its existing wrapper regression harness, so delegation would add handoff cost without independent ownership value.
- `scripts/refresh-dist.sh` now creates restart markers through `os.open(..., 0o600)` and enforces the final descriptor mode with `os.fchmod` before signalling Pi.
- `pi-extension/src/pi_restart_loop.test.ts` reproduces the refresh producer under umask `022`, proves the owner-only marker relaunches, and separately proves a group-readable matching marker is rejected.
- Regression evidence: the default-umask form using the old truncating producer failed with one launch instead of two before the fix. After the fix, `bash -n scripts/refresh-dist.sh`, `./node_modules/.bin/vitest run src/pi_restart_loop.test.ts` (5 tests), and `./node_modules/.bin/tsc --noEmit` all pass.
- Bounded inline review: the producer now meets the wrapper's exact `0600` postcondition, descriptors close on both success and failure, and the change does not broaden restart authorization.
