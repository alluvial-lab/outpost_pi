---
id: gate-refactor-lifecycle-debug-flush-dispose
kind: story
stage: done
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

## Implementation

- `DebugLog.close()` is now the idempotent awaited teardown contract: it rejects new admissions, cancels the debounce timer, and waits for the coalesced active/trailing snapshot drain and temporary-file cleanup.
- `dispose()` remains a synchronous compatibility wrapper that joins the same close future; `disposeDependencies()` awaits the logger before releasing injector-owned bindings.
- Regression coverage holds snapshot commit behind an explicit barrier, proves close cannot settle early, rejects post-close admissions, and verifies no temporary snapshot survives. The composition test now awaits `disposeDependencies()` directly without sleeps.
- Verified with the targeted debug-log suite, `flutter analyze`, the full non-E2E Flutter suite (952 tests), and the pi-extension typecheck/test/build pipeline (1,089 passed, 3 skipped).
