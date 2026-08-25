---
id: gate-refactor-lifecycle-debug-flush-dispose
kind: story
stage: implementing
tags: []
parent: null
depends_on: []
release_binding: v0.8.0
gate_origin: refactor
created: 2026-08-25
updated: 2026-08-25
---

# Give the debug flush drain an awaited teardown boundary

## Library
lifecycle

## Rule
resource-no-dispose

## Confidence
High

## Location
`app/lib/data/debug/debug_log_impl.dart:328`

## Issue
`dispose()` starts or joins `_flushNow()` and immediately returns, so the coalesced file-write drain and its temporary snapshot can outlive the service lifecycle with no owner awaiting completion.

## Impact
Routine tail events can be lost at shutdown, and a replacement logger can race an old writer that later renames a stale snapshot over newer diagnostic state.

## Fix
Expose an awaitable close/drain contract at the composition lifecycle, stop new admissions, await the active/trailing flush and temporary-file cleanup, then mark teardown complete; keep `dispose()` only as a safe compatibility wrapper if required.
