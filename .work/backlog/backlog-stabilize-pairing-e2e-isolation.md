---
id: backlog-stabilize-pairing-e2e-isolation
created: 2026-08-12
updated: 2026-08-12
tags: [app, bug]
---

# Stabilize pairing-e2e (parallel room-contamination flake)

## Origin
v0.4.0 push (2026-08-12): pairing-e2e CI failed (4 tests). Diagnosed as the known env-dependent flake, NOT a v0.4.0 regression — same commit 3bc9a970 (2026-08-07) produced push=success / PR=failure, and it was already red on 56c5701 (pre-v0.4.0 code). Relates to gate-tests-ci-lane-runs-env-dependent-e2e.

## Symptom
4 pairing/hydration E2E tests fail with SWAPPED room IDs (wc3B14rFnkrH <-> KzJ3MohnQOvq, one inverted) — parallel pairing tests against a shared source-built relay cross-pollinate room assignments. cross_room_pairing_e2e_test does expect(pairCode.qr.roomId, status.roomId); under contamination that flips.

## Location
app/test/e2e/* (pairing suite); app/dart_test.yaml (no e2e tag registered -> default parallelism; the run warned "e2e was used in the suite itself").

## Work
Isolate the E2E so rooms can't cross: either (a) serialize the e2e tag in dart_test.yaml (concurrency: 1 for e2e), or (b) spin a fresh source-built relay per test in the harness. Verify by running the suite reliably green across N consecutive CI runs. Prefer (b) if isolation is cheap; (a) is the minimal fix.
