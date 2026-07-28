---
id: gate-security-combined-app-verification-flaky
kind: story
stage: drafting
tags: [app, testing]
parent: null
depends_on: []
release_binding: null
gate_origin: security
created: 2026-07-19
updated: 2026-07-28
---

# Combined app verification command is flaky

## Source

Parked from the `standard`-weight cross-model review of
`feature-redact-secrets-from-diagnostic-surfaces` (2026-07-19). Lower-risk
finding — test-infrastructure, not a product defect.

## Finding

The exact two-file app verification command
(`flutter test --no-pub test/data/sync/sync_service_test.dart test/domain/contracts/debug_log_test.dart`)
failed once at `sync_service_test.dart:388` during review; the redaction
regression itself passed, and an isolated `sync_service_test.dart` rerun passed
all 91 tests. The checkout had concurrent uncommitted app-storage work at the
time, so this is not evidence of a redaction regression.

## Risk rationale (why parked, not fixed this cycle)

A flaky required command weakens future regression evidence, but it is a
test-isolation/stability issue, not a product bug. The redaction feature's own
tests pass reliably when run in isolation.

## Recommended direction

Investigate test isolation/ordering: the failure at line 388 under combined
execution suggests shared state or ordering sensitivity between the two files.
Stabilize by ensuring each test file is hermetic (no shared singleton state
leaking across files in the same process).
