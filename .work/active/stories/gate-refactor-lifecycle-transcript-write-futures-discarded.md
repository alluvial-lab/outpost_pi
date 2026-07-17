---
kind: story
release_binding: null
parent: feature-app-async-lifecycle-ownership
stage: done
id: gate-refactor-lifecycle-transcript-write-futures-discarded
tags: []
depends_on: []
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-17
---

# Transcript write futures are discarded from server-message handlers

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Location
app/lib/data/sync/sync_service.dart:549

## Issue
Server-message arms fire _appendTranscriptEvent(...) with // ignore: discarded_futures; handler-level errors are not explicitly awaited, returned, or handled.

## Fix
needs analysis

## Implementation

Closed by `feature-app-async-lifecycle-ownership-sync-failure-semantics`:
every server/timer transcript operation uses the named detached-write boundary,
emits a single visible degradation plus typed diagnostic on failure, requests
replay, and clears only after successful canonical persistence.
