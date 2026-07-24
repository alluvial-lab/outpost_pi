---
id: gate-refactor-lifecycle-resume-mesh-pull-floating
kind: story
stage: drafting
tags: []
parent: null
depends_on: []
release_binding: v0.3.0
gate_origin: refactor
created: 2026-07-20
updated: 2026-07-24
---

# Own the foreground-resume mesh pull future

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Location
`app/lib/main.dart:100`

## Issue
The resumed lifecycle branch discards `MeshSyncService.pullOnDemand()` behind a lint suppression, so an unexpected hash, fetch, verification, or storage exception is unobserved and races later pause/disposal work.

## Fix
Needs analysis: either await resume reconciliation through one lifecycle-owned serialized operation or wrap the pull in `unawaited` with explicit error reporting and generation/disposal checks appropriate to app lifecycle transitions.
