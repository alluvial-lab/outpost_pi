---
id: story-e2e-chaos-nightly-cadence
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

# Nightly seeded soak cadence

scripts/nightly_soak.sh + VM cron (idle window): fresh seed nightly, 15-min soak, report to rotated dir, triage summary, diff vs expected-findings list → alert file on drift (new findings OR missing expected). Acceptance: one manual-trigger run green; cron installed; rotation bounded.

## Integrity
Testing-integrity rules bind: discovered oddities parked with capture+triage evidence (never hidden, never gamed); xfail/skip-link known-open bugs; flip-on-fix wired.

## Verification
Device lane (e2e/run-live.sh semantics) green for whatever this story adds; unit tests where logic is pure; flutter analyze if Dart touched.

## Disk hygiene (added 2026-08-22 after ENOSPC incident)
Device-lane runs accumulate ~10-17G (app/build 4.4G, gradle build-cache growth, AVD userdata-qcow2 growth to 4.3G). The nightly script post-run: rm -rf app/build, clear ~/.gradle/caches/build-cache-1, wipe AVD userdata (disposable test state), verify df free-space floor (>10G) and alert below it.
