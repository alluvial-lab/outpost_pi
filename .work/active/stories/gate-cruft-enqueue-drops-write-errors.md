---
kind: story
release_binding: null
parent: feature-app-async-lifecycle-ownership
stage: done
id: gate-cruft-enqueue-drops-write-errors
tags: [cleanup]
depends_on: []
gate_origin: cruft
created: 2026-07-01
updated: 2026-07-17
---

# _enqueue drops write-chain exceptions

## Severity
Medium

## Location
app/lib/data/sync/sync_service.dart:1263

## Issue
_writeChain = next.catchError((Object _, StackTrace _) {}); discards all write errors, masking persistence/event failures and removing end-user/developer observability.

## Recommendation
Report and classify errors in the catch path, then continue the chain intentionally (e.g., emit diagnostics and return a neutral state).

## Implementation

Closed by `feature-app-async-lifecycle-ownership-sync-failure-semantics`:
`_enqueue` returns the real operation failure to awaited callers while retaining
only an error-absorbing predecessor for later work; detached owners classify and
diagnose their failures. Fail-once continuation tests pass.
