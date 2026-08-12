---
id: gate-refactor-restart-marker-cross-process-race
kind: story
stage: implementing
tags: [pi-extension, lifecycle]
parent: null
depends_on: []
release_binding: v0.4.0
gate_origin: refactor
created: 2026-08-11
updated: 2026-08-11
---

# Restart wrapper consumes any sibling Pi process's marker

## Severity
High (cross-gate corroboration: refactor High lifecycle, security Medium authz, tests High gap, cruft Medium stale-comment — one root cause).

## Location
scripts/pi-restart-loop.sh:57-70 (consumption). False comments at pi-extension/src/index.ts:2687-2690, scripts/pi-restart-loop.sh:11-13, scripts/hot-reload.sh:4-7.

## Evidence
The wrapper globs .restart-marker-* and consumes the first non-symlink without verifying the marker belongs to the child PID that just exited. With multiple Pi processes under the restart loop, process B's clean exit can consume process A's pending marker: B relaunches unexpectedly while A's wrapper stops after its intended hot-reload. The comments explicitly claim child-PID validation that does not exist.

## Remediation direction
Bind marker consumption to the exact exited child PID (match the marker suffix to the child); validate marker owner/mode/type before consuming; leave foreign markers untouched. Add tests: foreign-PID marker only, own+foreign present, no marker. Fix the false comments to describe the actual protocol.

## Test gap (folded in, tests gate T1)
pi-extension/src/pi_restart_loop.test.ts:13-60 only creates a matching marker; never exercises a foreign or stale marker.
