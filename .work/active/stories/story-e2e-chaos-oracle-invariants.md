---
id: story-e2e-chaos-oracle-invariants
kind: story
stage: done
tags: [testing]
parent: feature-e2e-chaos-expansion
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-21
updated: 2026-08-22
---

# Oracle invariants: replay dedup, DB↔UI consistency, ordering, identity stability

Extend the soak oracle + triage: (1) no-duplicate-delivery under reconnect replay (replayDedup events + transcript rows); (2) transcript-DB rows ↔ rendered bubbles consistency post-fault; (3) canonical server-ts ordering assertion (ties into the timestamp-ownership arc — flag violations, don't fix); (4) identity stability: owner/pair identity never silently regenerates across any fault sequence. Each invariant: triage detection + soak assertion + unit test where pure logic. Acceptance: short seeded soak green with all invariants exercised; triage selftest extended.

## Integrity
Testing-integrity rules bind: discovered oddities parked with capture+triage evidence (never hidden, never gamed); xfail/skip-link known-open bugs; flip-on-fix wired.

## Verification
Device lane (e2e/run-live.sh semantics) green for whatever this story adds; unit tests where logic is pure; flutter analyze if Dart touched.

## Implementation

- Execution capability: `openai-codex/gpt-5.6-sol` at high reasoning; direct-read implementation because the oracle, triage, and generated device test are one cohesive boundary.
- Review weight: standard project default; not applicable independently because this is a child-story checkpoint.
- Landed four content-free oracle checks in `e2e/live_soak.py`: replay acceptance and transcript-id uniqueness, transcript-DB ↔ `ChatReady` projection identity/order consistency plus a materialized newest bubble, nondecreasing canonical timestamps with sequence tie order, and full owner/pair/channel identity stability against a pre-fault baseline. The temporary generated Dart test emits bounded ID/timestamp/public-key-tail observations; no production Dart source changed.
- Extended `scripts/debug_capture_triage.py` to consume those observations with `--oracle`, correlate them with capture-ring `replayDedup` rows, report each invariant independently, and make any violation anomalous. The checked-in selftest now proves positive and negative cases for all four invariants.
- Added pure Python coverage in `e2e/test_live_soak.py` for clean and violating replay/DB↔UI/order/identity observations, marker parsing, and generated-device assertion presence.
- Verification: `python3 -m unittest e2e.test_live_soak` passed 8 tests; `python3 scripts/debug_capture_triage.py --selftest` passed all checks; generated temporary Dart analyzed with no issues. No maintained Dart file changed, so the full app analyzer was not required.
- Short seeded device evidence: seed `20260822`, 180-second schedule, device phase green in 03:12; `.work/session-notes/live-soak-20260822-oracle-faults/report.md` records 133 `replayDedup` observations and 10 oracle checkpoints with replay dedup, DB↔UI, ordering, and identity all `ok`.
- Simplification/discrepancies: no production logging variant or duplicated wire contract was added; test-only content-free observations bridge the live UI/DB boundary into the existing triage tool. No design discrepancy.
- Parked findings: no new invariant violation. The seeded identity-window probe reproduced the already-linked `story-app-send-swallowed-session-identity-unavailable`; no duplicate backlog item was created.
