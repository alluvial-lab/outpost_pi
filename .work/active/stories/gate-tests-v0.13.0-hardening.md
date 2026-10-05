---
id: gate-tests-v0.13.0-hardening
kind: story
stage: done
tags: [testing]
parent: null
depends_on: []
release_binding: v0.13.0
gate_origin: tests
created: 2026-10-05
updated: 2026-10-05
---

# gate-tests v0.13.0: diagnostic-integration and wake-wiring test hardening

Consolidated findings from the v0.13.0 tests gate (deep scanner, cross-model).
All critical findings fixed in-gate; medium/low dispositions inline.

## Findings and dispositions

1. **[critical] ConnCancelEvent routing test misidentified the superseding
   attempt** (`_assertEvent` firstWhere picked the initial connect's rows;
   also `requiredSites` lacked a connCancel entry; also the
   `allVariants()` fixture list never constructed the new event).
   FIXED: generation-matched assertions; requiredSites entry;
   allVariants fixture. Two extra production refinements fell out:
   cancel-site rows are now suppressed when no prior attempt existed
   (first connects no longer emit phantom supersession events), and the
   lifecycle prefix assertion filters the orthogonal connCancel stream.
   Exit-code lesson recorded: earlier "green" runs were tail-masked.
2. **[critical] Local-only wake protection tested only at the predicate, not
   the wiring** — FIXED structurally: the wiring moved out of the
   unimportable script into `createWakeCoordinator` (wake.ts) with injected
   scheduler/clock; boundary tests cover remote-only (no wake, drainable),
   local-behind-remote (one wake naming the local sender, no body/id
   sentinels in reach of the nudge), and burst coalescing.
3. **[critical] Deferred-wake liveness had no timer/drain integration test**
   — FIXED by the same seam: fake-scheduler tests cover capped-edge → armed
   → fire-without-arrival → one liveness wake; drain-before-fire cancels;
   early-fire (skew) re-arms instead of forcing or dropping.
4. **[medium] Inbox eviction × wake eligibility untested interaction** —
   FIXED: eviction test (capped local shed by a remote flood → no
   remote-triggered wake, drop count surfaced, later local still wakes).
5. **[medium] Byte-overflow oracle permitted exceeding the budget** — FIXED:
   retained-byte-sum ≤ budget assertion + exact suffix + drop count.
6. **[medium] supervisorInvalidate attribution path had no assertion** —
   FIXED: dispose-with-in-flight-factory routing scenario.
7. **[low] Ephemeral-config wx assertion tested Node, not the writer** —
   FIXED: two-config distinct-dirs + exact execution-bearing JSON contents +
   removal assertions.

## Verification

typecheck + targeted 39/39; full extension + full app suites run post-fix
(records in the release body).
