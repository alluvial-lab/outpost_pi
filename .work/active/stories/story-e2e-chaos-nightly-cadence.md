---
id: story-e2e-chaos-nightly-cadence
kind: story
stage: done
tags: [testing]
parent: feature-e2e-chaos-expansion
depends_on: [story-e2e-chaos-oracle-invariants, story-e2e-chaos-fault-vocabulary]
release_binding: null
gate_origin: null
created: 2026-08-21
updated: 2026-08-23
---

# Nightly seeded soak cadence

scripts/nightly_soak.sh + VM cron (idle window): fresh seed nightly, 15-min soak, report to rotated dir, triage summary, diff vs expected-findings list → alert file on drift (new findings OR missing expected). Acceptance: one manual-trigger run green; cron installed; rotation bounded.

## Integrity
Testing-integrity rules bind: discovered oddities parked with capture+triage evidence (never hidden, never gamed); xfail/skip-link known-open bugs; flip-on-fix wired.

## Verification
Device lane (e2e/run-live.sh semantics) green for whatever this story adds; unit tests where logic is pure; flutter analyze if Dart touched.

## Disk hygiene (added 2026-08-22 after ENOSPC incident)
Device-lane runs accumulate ~10-17G (app/build 4.4G, gradle build-cache growth, AVD userdata-qcow2 growth to 4.3G). The nightly script post-run: rm -rf app/build, clear ~/.gradle/caches/build-cache-1, wipe AVD userdata (disposable test state), verify df free-space floor (>10G) and alert below it.

## Implementation

- Execution capability: `openai-codex/gpt-5.6-sol` at high reasoning; direct implementation because the scheduler wrapper, findings reconciliation, cron entry, and device cleanup are one serial operational boundary.
- Review weight: standard project default; not applicable independently because this is a child-story checkpoint.
- Added `scripts/nightly_soak.sh`: cryptographically fresh seed, 900-second default, per-run reports below a newest-14 bounded directory, machine-readable findings reconciliation, summary/alert artifacts, and environment overrides for duration, retention, report root, and manifest.
- Added `e2e/expected-soak-findings.txt` and `scripts/nightly_soak_report.py`. The inventory covers all five currently open live-lane findings: the swallow/blank-chat pair, grid cold replay dedup, mesh roster bootstrap, and the already-parked session-rotation late-echo working bug. Known-open presence is reported and does not fail the soak; new or missing inventory ids, unexpected runner/oracle failures, and targeted-finding absences alert and exit nonzero.
- Extended `e2e/live_soak.py` to emit `findings.json`, report known-open presence separately from in-lane observation, preserve the linked state-rotation skip, and wait for actual bubble materialization at the async UI boundary. Pure reconciliation/inventory tests were added to `e2e/test_live_soak.py`.
- Installed the VM cron entry at 02:30 local while preserving the existing disk guard: `30 2 * * * .../scripts/nightly_soak.sh ... # outpost-pi-nightly-soak`. `e2e/README.md` documents the cadence, overrides, report semantics, and serial-device constraint.
- Disk hygiene runs after successful or failed device execution: emulator shutdown is verified, `app/build` and `~/.gradle/caches/build-cache-1` are removed, disposable AVD writable userdata/overlays are reset, and a free-space floor strictly greater than 10 GiB is enforced through the alert path.
- Verification: final manual seed `362604294` ran the full 900-second schedule green (device span 15:05; 1,790 capture rows; 775 replay-dedup observations; 23 oracle checkpoints; all four invariants `ok`). `.work/session-notes/nightly-soak/run-20260822T201229Z-362604294/{report.md,summary.md}` records zero drift/unexpected/suspicious findings and the two expected in-lane observations. Post-run: emulator down, build/cache/userdata removed, 40 GiB free.
- Tests: `python3 -m unittest e2e.test_live_soak` passed 14 tests; triage selftest passed all checks; shell syntax, Compose skew config, Python compile, and `git diff --check` passed. `shellcheck` is unavailable on the VM. No maintained Dart source changed, so Flutter analyze was not required.
- Verification discovery: the first manual attempt exposed an async baseline check that inspected the bubble before materialization; it was fixed with a bounded pump. The second reached the pre-existing linked session-rotation working bug; the full soak now carries the same explicit skip-link as the dedicated state-shape lane rather than treating the known product defect as a novel runner failure. No new product oddity was found.
- Simplification/discrepancies: one checked-in manifest is the expected-inventory source; known-open status and per-run observation are deliberately separate so out-of-lane mesh/grid bugs can remain flip-on-fix tracked without pretending a single-Pi process-live soak reproduced them. The inventory contains five rather than the four explicitly called out because `backlog-app-session-rotation-late-echo-sticks-working` is also currently open and already linked by the full-soak state shape.
- Adjacent issues parked: none; every observed product issue was already parked with evidence.

### Review closure

- Replaced the five-id handwritten runtime inventory with direct loading from the canonical six-id `e2e/expected-soak-findings.txt` manifest, adding `backlog-app-reconnect-churn-timeout-lifecycle-failures`; the unit contract now asserts that real manifest's exact open set.
- Host-timestamped scheduled fault windows now reconcile triage churn. The final 300-second seed `20260823` run recorded one three-loss churn cluster wholly inside scheduled fault/recovery windows, rendered it as `Anomalies: RECONCILED`, and exited 0 with no suspicious/unexpected findings; outside-window clusters remain fail-closed unexpected findings.
- Narrowed the oracle to DB↔`ChatReady` ViewModel projection consistency and added widget traversal that materializes every renderable maintained bubble id and checks materialized newest-to-oldest order before restoring the newest view.
- The full soak now executes the real `exerciseMultiSessionShape` A→B→A path. Evidence contains `SOAK_STATE_SHAPE multi_session_round_trip started` and `exercised`; the timing-dependent known-finding marker is emitted only from the real exercise's `workingConverged` observation.
- Added per-serial `flock` ownership and recorded runner/emulator PIDs. A concurrent second runner exited 2 while the first remained alive and `emulator-5554` stayed `device` before/after; cleanup now terminates only the run-owned emulator process group. Nightly waits or alerts/skips without touching an occupied lane.
- Nightly now has a 40-minute outer timeout, EXIT-trap hygiene, retained cron output, append/rotated `LATEST_ALERT.md`, and timestamped `LAST_STATUS`. The installed 02:30 cron entry now appends to `.work/session-notes/nightly-soak/cron.log`.
- Verification evidence: `.work/session-notes/review-closure-soak-final-20260823/` (734 capture rows, 187 replay-dedup observations, 11 oracle checkpoints, six known-open ids, zero unexpected/suspicious findings); `python3 -m unittest e2e.test_live_soak` passed 15 tests; triage selftest and `flutter analyze` passed. Post-device hygiene left the emulator down, removed build/cache/AVD writable state, and restored 39 GiB free.
