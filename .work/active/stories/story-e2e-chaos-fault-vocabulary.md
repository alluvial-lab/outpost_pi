---
id: story-e2e-chaos-fault-vocabulary
kind: story
stage: implementing
tags: [testing]
parent: feature-e2e-chaos-expansion
depends_on: story-e2e-chaos-oracle-invariants
release_binding: null
gate_origin: null
created: 2026-08-21
updated: 2026-08-21
---

# Fault vocabulary: degradation toxics, relay kill, compound faults

faults.sh: latency, bandwidth, slow_close toxics; relay_kill (docker kill + restart) distinct from pause; compound application helper (apply N faults). live_soak scheduler: new classes + weights + compound picks; determinism tests updated. Acceptance: each class demonstrated in a short soak; unit tests green.

## Integrity
Testing-integrity rules bind: discovered oddities parked with capture+triage evidence (never hidden, never gamed); xfail/skip-link known-open bugs; flip-on-fix wired.

## Verification
Device lane (e2e/run-live.sh semantics) green for whatever this story adds; unit tests where logic is pure; flutter analyze if Dart touched.
