---
id: gate-refactor-restart-marker-cross-process-race
kind: story
stage: done
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

## Implementation notes
- Execution capability: inline host execution; the lifecycle race was cohesive across one wrapper, its focused process harness, and protocol comments.
- Review weight: standard (project default), using the required bounded inline standalone-story review with no independent reviewer.
- Files changed: `scripts/pi-restart-loop.sh` now runs Pi through a foreground exec shim that records the exact child PID, accepts only `.restart-marker-<child-PID>`, and validates marker type, owner, and mode; `pi-extension/src/pi_restart_loop.test.ts` covers stale foreign-only, own-plus-foreign, no-marker, insecure matching-marker, and fresh-session flows; `scripts/hot-reload.sh` and `pi-extension/src/index.ts` now describe the implemented PID handshake.
- Tests added/removed: expanded the restart-loop harness from one matching-marker case to five lifecycle/validation cases; removed none.
- Verification: `bash -n scripts/pi-restart-loop.sh scripts/hot-reload.sh` passed; `./node_modules/.bin/vitest run src/pi_restart_loop.test.ts` passed (5 tests); `./node_modules/.bin/tsc --noEmit` passed.
- Simplification: removed marker globbing entirely; authorization is one exact path derived from the recorded child PID.
- Discrepancies from design: none.
- Adjacent issues parked: none.

## Bounded inline review
Approved. The exec shim preserves foreground TUI ownership while making the exited PID explicit; foreign markers are untouched, malformed matching markers fail closed, and only exit code 0 plus the exact validated marker relaunches with `--continue`.
