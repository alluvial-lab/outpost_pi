---
id: gate-docs-e2e-readme-empty-soak-inventory
kind: story
stage: done
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.8.0
gate_origin: docs
created: 2026-08-25
updated: 2026-08-25
---

# E2E README describes a six-id known-open inventory and exit path that no longer exist

## Drift category
readme-staleness

## Location
- Doc: `e2e/README.md:62-67,77-85`
- Contradicting source: `e2e/expected-soak-findings.txt:1` (empty); `e2e/live_soak.py:1225-1300`; `e2e/test_live_soak.py:142-150`

## Current doc text
> Exit `3` means a linked, deterministically targeted finding was absent ...
>
> The canonical six-id inventory is `e2e/expected-soak-findings.txt`; `live_soak.py` loads that manifest directly. A known bug is reported without failing the soak.

## Contradiction
The canonical manifest is now empty, and the runner no longer populates `suspicious` from an expected-finding set. With no known-open IDs, observations are unexpected and fail the soak; the checked-in test asserts the empty inventory. The README still presents the retired six-id inventory and its old exit-3 semantics as current behavior.

## Required edit
Describe the current empty known-open inventory and current failure behavior: unexpected observations fail the run, while the manifest remains the source of truth if a new finding is deliberately opened. Remove the claim that a linked absence currently produces exit `3`.

## Implementation
- Rewrote the soak README inventory and exit semantics to match the empty manifest and fail-on-unexpected behavior.
