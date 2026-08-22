---
id: story-e2e-chaos-oracle-invariants
kind: story
stage: implementing
tags: [testing]
parent: feature-e2e-chaos-expansion
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-21
updated: 2026-08-21
---

# Oracle invariants: replay dedup, DB↔UI consistency, ordering, identity stability

Extend the soak oracle + triage: (1) no-duplicate-delivery under reconnect replay (replayDedup events + transcript rows); (2) transcript-DB rows ↔ rendered bubbles consistency post-fault; (3) canonical server-ts ordering assertion (ties into the timestamp-ownership arc — flag violations, don't fix); (4) identity stability: owner/pair identity never silently regenerates across any fault sequence. Each invariant: triage detection + soak assertion + unit test where pure logic. Acceptance: short seeded soak green with all invariants exercised; triage selftest extended.

## Integrity
Testing-integrity rules bind: discovered oddities parked with capture+triage evidence (never hidden, never gamed); xfail/skip-link known-open bugs; flip-on-fix wired.

## Verification
Device lane (e2e/run-live.sh semantics) green for whatever this story adds; unit tests where logic is pure; flutter analyze if Dart touched.
