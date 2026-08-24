---
id: gate-tests-nightly-findings-fail-closed
kind: story
stage: implementing
tags: [testing, workflow]
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: tests
created: 2026-08-24
updated: 2026-08-24
---

# Make the nightly findings reconciler prove every alert class fails closed

## Priority
High

## Value evidence
Item: `story-e2e-chaos-nightly-cadence`. Its contract says new/missing inventory,
unexpected invariant/environment findings, and suspicious targeted absences all
alert and exit nonzero. `load_findings` requires `unexpected` and `suspicious`,
and the summary displays them, but `nightly_soak_report.py` returns failure only
for new/missing ids or a nonzero runner status
(`scripts/nightly_soak_report.py:85-109`). The only reconciliation unit test
covers new/missing inventory with both alert lists empty
(`e2e/test_live_soak.py:240-251`). A producer/exit-code drift could therefore
turn a non-empty machine-readable alert payload into a green nightly report.

## Gap type
important-interface / test-oracle false-negative

## Suggested test
```python
# Invoke the reporter's status decision (or CLI in a temp directory) with:
# clean; new; missing; runner failure; unexpected-only; suspicious-only;
# malformed/missing findings. Assert clean=0 and every alert/error case != 0,
# while the summary retains the bounded finding text/counts. The unexpected-only
# and suspicious-only cases should fail before the reporter is hardened.
```

## Test location (suggested)
`e2e/test_live_soak.py`
