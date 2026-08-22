---
id: story-e2e-chaos-state-shapes
kind: story
stage: implementing
tags: [testing]
parent: feature-e2e-chaos-expansion
depends_on: [story-e2e-chaos-oracle-invariants, story-e2e-chaos-fault-vocabulary]
release_binding: null
gate_origin: null
created: 2026-08-21
updated: 2026-08-21
---

# State shapes: multi-session, re-pair cycles, long uptime

Soak state shapes + scenarios: (1) multi-session switching under faults (A→B→A; per-session projection + working correctness — highest-confidence oddity finder); (2) re-pair cycle mid-conversation (identity continuity, transcript survival); (3) long-uptime shape with ring rotation + replay. Acceptance: scenarios green (or oddities parked with evidence); soak runs the new shapes.

## Integrity
Testing-integrity rules bind: discovered oddities parked with capture+triage evidence (never hidden, never gamed); xfail/skip-link known-open bugs; flip-on-fix wired.

## Verification
Device lane (e2e/run-live.sh semantics) green for whatever this story adds; unit tests where logic is pure; flutter analyze if Dart touched.
