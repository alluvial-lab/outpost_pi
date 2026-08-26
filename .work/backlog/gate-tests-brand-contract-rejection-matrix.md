---
id: gate-tests-brand-contract-rejection-matrix
created: 2026-08-26
updated: 2026-08-26
tags: [testing, branding, workflow]
release_binding: null
gate_origin: tests
---

# Brand-contract boundary lacks a rejection matrix for CSS and SVG projection drift

## Priority
Medium

## Value evidence
Item: `feature-theme-token-cross-surface-contract-contract-tooling`.

Contract / risk / maintenance cost: the deliberately restricted parser is the release's fail-fast boundary: missing, duplicate, unsupported, or non-color CSS roles and structurally drifted SVG projections must fail instead of producing partial cross-surface contracts (`.work/active/features/feature-theme-token-cross-surface-contract.md:71-148`). `scripts/brand_contract.py:128-273` implements the CSS grammar and `:516-657` independently validates four checked SVG projections. The five current tests cover a stale generated fixture, one extra selector, one canonical-SVG attribute, one missing canonical primitive, and deterministic output (`scripts/test_brand_contract.py:31-89`); none drives missing/duplicate/bad-value/media-mismatch CSS partitions or `validate_mark_projection` geometry/transform drift. Those branches defend a custom parser rather than incidental implementation lines, so a compact rejection matrix would materially protect the contract.

Focused gate evidence: `python3 -m unittest scripts/test_brand_contract.py` passed 5/5 and the checked projections were fresh.

## Gap type
complex-unit / invalid-input partitions / generated-contract seam

## Suggested test
```python
def test_restricted_css_rejection_matrix(self):
    # Table-drive: missing allowlisted role, duplicate role, unknown --color-*,
    # invalid hex/rgba channel, and dark media/root disagreement. Each case must
    # raise ContractError naming the offending selector/token.

def test_checked_svg_projection_drift_is_rejected(self):
    # Copy a real projection, then independently perturb edge geometry, hub/peer
    # geometry, viewBox, and the banner transform. validate_mark_projection must
    # reject each case while the unmodified projection passes.
```

## Test location (suggested)
`scripts/test_brand_contract.py`
