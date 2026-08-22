---
id: story-e2e-chaos-fault-vocabulary
kind: story
stage: done
tags: [testing]
parent: feature-e2e-chaos-expansion
depends_on: story-e2e-chaos-oracle-invariants
release_binding: null
gate_origin: null
created: 2026-08-21
updated: 2026-08-22
---

# Fault vocabulary: degradation toxics, relay kill, compound faults

faults.sh: latency, bandwidth, slow_close toxics; relay_kill (docker kill + restart) distinct from pause; compound application helper (apply N faults). live_soak scheduler: new classes + weights + compound picks; determinism tests updated. Acceptance: each class demonstrated in a short soak; unit tests green.

## Integrity
Testing-integrity rules bind: discovered oddities parked with capture+triage evidence (never hidden, never gamed); xfail/skip-link known-open bugs; flip-on-fix wired.

## Verification
Device lane (e2e/run-live.sh semantics) green for whatever this story adds; unit tests where logic is pure; flutter analyze if Dart touched.

## Implementation

- Execution capability: `openai-codex/gpt-5.6-sol` at high reasoning; direct implementation because the shell fault adapter, scheduler, generated test, and evidence parser form one serial device-lane boundary.
- Review weight: standard project default; not applicable independently because this is a child-story checkpoint.
- Landed latency, bandwidth, and slow-close Toxiproxy controls in `e2e/lib/faults.sh`, plus validated multi-toxic `net_compound` application and abrupt `relay_kill`/restart distinct from pause/unpause. `e2e/run-live.sh` now admits the bounded command vocabulary and records successfully applied requests in the run artifacts.
- Extended the deterministic scheduler with tuned network/class weights, randomized two/three-toxic compounds, relay-kill picks, and a short-run probe block that guarantees acceptance coverage. The report fails when a scheduled demonstration was not actually applied. Relative artifact paths are resolved before the runner changes cwd, fixing the post-run evidence miss discovered during verification.
- Tests: `python3 -m unittest e2e.test_live_soak` passed 11 tests; `python3 scripts/debug_capture_triage.py --selftest` passed all 10 checks; `bash -n e2e/lib/faults.sh e2e/run-live.sh` passed; the generated 180-second Dart test analyzed with no issues. No maintained Dart file changed, so full `flutter analyze` was not required. `shellcheck` was unavailable on the host.
- Short seeded soak: seed `20260822`, 180-second device phase green in 03:12. `.work/session-notes/live-soak-20260822-oracle-faults/report.md` records latency, bandwidth, slow-close, compound latency+bandwidth, and relay-kill as applied; all four oracle invariants were `ok`. The first post-run aggregation returned 1 only because the caller supplied a relative artifact path that the runner interpreted after changing to `app/`; the path fix landed and the same complete artifacts reprocessed cleanly, without spending a second device run.
- Disk hygiene: the runner had already stopped the emulator; the explicit `adb emu kill` confirmed no serial remained, `app/build` was removed, and `df -h /` reported 16G free.
- Simplification/discrepancies: one `_net_apply` primitive owns both singular and compound toxic construction; hard-down is rejected from compounds because it would make peer toxics inert. No product code or protocol contract changed.
- Parked findings: no new invariant violation. The run reproduced the already-linked send-swallow finding; no duplicate backlog item was created.
