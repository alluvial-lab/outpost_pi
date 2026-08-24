---
id: story-e2e-chaos-state-shapes
kind: story
stage: done
tags: [testing]
parent: feature-e2e-chaos-expansion
depends_on: [story-e2e-chaos-oracle-invariants, story-e2e-chaos-fault-vocabulary]
release_binding: v0.7.0
gate_origin: null
created: 2026-08-21
updated: 2026-08-22
---

# State shapes: multi-session, re-pair cycles, long uptime

Soak state shapes + scenarios: (1) multi-session switching under faults (A→B→A; per-session projection + working correctness — highest-confidence oddity finder); (2) re-pair cycle mid-conversation (identity continuity, transcript survival); (3) long-uptime shape with ring rotation + replay. Acceptance: scenarios green (or oddities parked with evidence); soak runs the new shapes.

## Integrity
Testing-integrity rules bind: discovered oddities parked with capture+triage evidence (never hidden, never gamed); xfail/skip-link known-open bugs; flip-on-fix wired.

## Verification
Device lane (e2e/run-live.sh semantics) green for whatever this story adds; unit tests where logic is pure; flutter analyze if Dart touched.

## Implementation

- Added `live_state_shapes_test.dart` plus the `state-shapes` runner selector. The live harness now drives production typed `session_new`, an external Pi-style retained-session resume, local unpair/re-pair with fresh owner-channel keys, transcript projection reads by canonical session, and bounded capture-ring/replay probes.
- Full soaks schedule deterministic multi-session and long-uptime replay shapes at the 300-second threshold; scheduler generation remains seeded and unit-tested.
- The first A→B run found `backlog-app-session-rotation-late-echo-sticks-working`: after an authoritative `working=false`, a duplicate late echo re-opened the app backstop and never reconverged. Capture and triage evidence live in `.work/session-notes/live-state-shapes-20260822/`. The correct multi-session assertion remains skip-linked; re-pair and ring-rotation/replay scenarios pass independently.
- Added a process-local retained-session switch seam to the narrow Pi-host test adapter. It models external `/resume` without adding a production wire action.

Verification (2026-08-22):

- `e2e/run-live.sh state-shapes` — green: 2 passed, 1 known-bug-linked skip; capture pulled. Re-pair identity/transcript continuity and 1 MiB ring rotation plus reconnect replay passed.
- `python3 -m unittest e2e.test_live_soak` — 12 passed.
- `flutter analyze` — no issues.
- Pi-host test-support TypeScript compile (`node_modules/.bin/tsc -p ../e2e/tsconfig.pi-host.json`) — passed.
