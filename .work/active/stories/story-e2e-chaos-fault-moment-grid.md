---
id: story-e2e-chaos-fault-moment-grid
kind: story
stage: implementing
tags: [testing]
parent: feature-e2e-chaos-expansion
depends_on: story-e2e-chaos-fault-vocabulary
release_binding: null
gate_origin: null
created: 2026-08-21
updated: 2026-08-21
---

# Deterministic fault×moment grid

Short deterministic scenarios: each fault class × lifecycle moment (pairing handshake, hydration window, QR scan, mid-turn staged, cold-open). New test file + runner selector; no randomization. Acceptance: grid executes end-to-end; every cell passes or parks an oddity with capture evidence.

## Integrity
Testing-integrity rules bind: discovered oddities parked with capture+triage evidence (never hidden, never gamed); xfail/skip-link known-open bugs; flip-on-fix wired.

## Verification
Device lane (e2e/run-live.sh semantics) green for whatever this story adds; unit tests where logic is pure; flutter analyze if Dart touched.
