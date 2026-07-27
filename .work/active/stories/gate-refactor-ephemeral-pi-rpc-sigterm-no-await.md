---
id: gate-refactor-ephemeral-pi-rpc-sigterm-no-await
kind: story
stage: done
tags: [refactor]
parent: null
depends_on: []
release_binding: cockpit-v0.3.0
gate_origin: refactor
created: 2026-07-27
updated: 2026-07-27
---

# Ephemeral pi RPC dispose sends SIGTERM without awaiting or escalating

## Library
lifecycle

## Rule
resource-no-dispose

## Confidence
High

## Location
`cockpit/lib/app/core/data/relay/ephemeral_pi_rpc.dart:108-127`

## Issue
After the graceful two-second wait times out, `dispose()` sends SIGTERM but
does not await exit, escalate to SIGKILL, or confirm termination before
deleting the working directory. The owned `pi --mode rpc` child can survive
disposal.

## Fix
Await termination after SIGTERM, escalate to SIGKILL on a second timeout,
await the final exit, then cancel streams and remove the temporary
directory.

## Implementation notes
- `dispose()` now waits for graceful exit, then SIGTERM exit, then escalates to SIGKILL and waits for the child's final exit before releasing stream subscriptions and its temporary directory.
- Added an owned-process starter seam and deterministic fake-process tests: an ignored SIGTERM reaches SIGKILL and retains the working directory until final exit; a graceful exit sends no signal.
- Verification: `flutter test test/core/data/relay/ephemeral_pi_rpc_test.dart` passed.

## Review

Bounded inline review (orchestrator, 2026-07-27): diffs inspected —
serialized finalizer with _closed re-checks after every await, SIGTERM
await + SIGKILL escalation + final-exit await before dir removal, stale
pair-code row removed. Orchestrator-verified: flutter analyze clean, 267
tests green (incl. new deterministic fake-process and interleaving tests).
Approved -> done.
