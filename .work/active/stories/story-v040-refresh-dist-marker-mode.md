---
id: story-v040-refresh-dist-marker-mode
kind: story
stage: implementing
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
