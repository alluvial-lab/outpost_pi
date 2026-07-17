---
kind: story
release_binding: null
parent: feature-app-async-lifecycle-ownership
stage: done
id: gate-refactor-lifecycle-peer-mesh-publish-dropped
tags: []
depends_on: []
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-17
---

# Peer mutation hook drops async mesh publish failures

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Location
app/lib/config/dependencies.dart:98

## Issue
The sync attachPeerMutationHook callback calls async meshSync.publish() with only a lint ignore. The returned Future<MeshPublishResult> and any thrown error are discarded.

## Fix
needs analysis

## Implementation

Closed by `feature-app-async-lifecycle-ownership-mesh-publication`:
`PairingStorage` now passes typed mutation intent into the synchronous
`MeshSyncService.publishAfterPeerMutation` boundary. Mesh sync owns every
publish result, coalesces concurrent mutations, retries transient failures via
one lifecycle-owned timer, diagnoses permanent outcomes, and cancels pending
work on disposal. DI attaches the method directly and discards no future.
