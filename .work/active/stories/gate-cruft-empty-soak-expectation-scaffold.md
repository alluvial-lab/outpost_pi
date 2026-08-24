---
id: gate-cruft-empty-soak-expectation-scaffold
kind: story
stage: implementing
tags: [cleanup]
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: cruft
created: 2026-08-24
updated: 2026-08-24
---

# Remove the empty targeted-finding branch from the live soak

## Confidence
High

## Category
dead diagnostic scaffolding; stale comment

## Location
- `e2e/live_soak.py:65-70`
- `e2e/live_soak.py:1257-1268`
- `e2e/expected-soak-findings.txt:1`

## Finding
The soak still carries two empty targeted-finding sets and a report/runtime
branch that only iterates those sets. The adjacent comments say the long soak
carries a late-echo known-open skip “until its working bug is fixed”, but the
late-echo fix landed in this delta and removed the finding from the manifest. The
checked-in expected-findings manifest is now empty, so this branch cannot produce
a current report, warning, or failure.

## Evidence
```python
# ... until its working bug is fixed.
SOAK_EXPECTED_FINDINGS: frozenset[str] = frozenset()
# ... linked late-echo defect is timing-dependent ...
SOAK_LONG_EXPECTED_FINDINGS: frozenset[str] = frozenset()
```

```python
expected_findings = set(SOAK_EXPECTED_FINDINGS)
if duration >= STATE_SHAPE_PROBE_DURATION_SECONDS:
    expected_findings.update(SOAK_LONG_EXPECTED_FINDINGS)
for key in expected_findings:
    ...
```

## Removal rationale
Delete the stale comments, both permanently empty sets, and the no-op
`expected_findings`/suspicious-absence loop. Keep the manifest-backed
`FINDING_OBSERVATIONS` reporting and invariant/churn checks. If a future finding
is intentionally targeted by this in-process lane, add an explicit expectation
with that finding rather than retaining an always-empty compatibility branch.

## Risk
Current release behavior is unchanged because the manifest and both sets are
empty. A future targeted finding would no longer get an absence warning until a
new explicit expectation is added; that is an intentional fail-closed design
choice, not a silent pass.
