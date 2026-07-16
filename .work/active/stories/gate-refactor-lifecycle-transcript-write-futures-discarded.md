---
kind: story
release_binding: null
parent: feature-app-async-lifecycle-ownership
stage: drafting
id: gate-refactor-lifecycle-transcript-write-futures-discarded
tags: []
depends_on: []
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-01
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
