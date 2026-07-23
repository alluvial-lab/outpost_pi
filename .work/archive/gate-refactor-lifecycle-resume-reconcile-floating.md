---
id: gate-refactor-lifecycle-resume-reconcile-floating
kind: story
stage: drafting
tags: []
parent: null
depends_on: []
release_binding: null
gate_origin: refactor
created: 2026-07-20
updated: 2026-07-20
---

# Own foreground connection reconciliation across lifecycle transitions

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Location
`app/lib/main.dart:102`

## Issue
`didChangeAppLifecycleState` discards `reconcileOnAppResume()` behind a lint suppression even though its hydration, reconnect, and boot awaits can fail or complete after a later pause/detach transition.

## Fix
Needs analysis: give resume reconciliation a generation-guarded owner that observes failures and prevents stale completion after a newer lifecycle state, using explicit `unawaited` only after that owner contains its error policy.
