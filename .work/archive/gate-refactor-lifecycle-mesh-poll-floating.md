---
id: gate-refactor-lifecycle-mesh-poll-floating
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

# Observe periodic mesh pull completion and failures

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Location
`app/lib/data/mesh/mesh_sync_service.dart:545`

## Issue
The periodic polling callback discards `pullOnDemand()` behind a lint suppression, leaving unexpected asynchronous failures unobserved and allowing overlapping timer ticks to race without an explicit ownership policy.

## Fix
Needs analysis: route timer ticks through a service-owned single-flight poll operation that catches and diagnoses unexpected failures, checks disposal after async gaps, and explicitly marks the detached future with `unawaited`.
