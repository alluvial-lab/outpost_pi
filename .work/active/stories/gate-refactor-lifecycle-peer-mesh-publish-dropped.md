---
kind: story
release_binding: null
parent: feature-app-async-lifecycle-ownership
stage: drafting
id: gate-refactor-lifecycle-peer-mesh-publish-dropped
tags: []
depends_on: []
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-01
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
