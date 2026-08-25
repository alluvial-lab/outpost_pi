---
id: gate-refactor-lifecycle-workspace-file-watch-debounce-floating
status: superseded
superseded_by: backlog-cockpit-file-watch-reliability (groom merge d4d514e, 2026-07-22)
created: 2026-07-20
updated: 2026-07-24
tags: []
release_binding: null
gate_origin: refactor
---

# Own asynchronous file-watch reload timer work

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Location
`cockpit/lib/app/cockpit/ui/viewmodels/workspace_projection.dart:445`

## Issue
The file-watch debounce passes an `async` callback directly to `Timer`, whose void callback contract discards the returned future, so reader failures are unobserved and the reload has no explicit async ownership boundary.

## Fix
Needs analysis: move the reload into an owned async operation with explicit failure observation and preserve the existing item-identity checks, debounce cancellation, and projection teardown ordering.

## Relevance
Ambient. The timer callback predates the `cockpit-v0.2.0` bundle; the release changed the adjacent agent-startup close fence, not this callback.

## Gate run note
The scanner ran inline at the operator's direction rather than in an isolated scanner sub-agent; this finding therefore has reduced review isolation.
