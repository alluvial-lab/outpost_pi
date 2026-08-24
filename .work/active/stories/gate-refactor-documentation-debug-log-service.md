---
id: gate-refactor-documentation-debug-log-service
kind: story
stage: implementing
tags: [refactor]
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: refactor
created: 2026-08-24
updated: 2026-08-24
---

# Attach the debug-log service contract to its public implementation

## Library
documentation

## Rule
exported-type

## Confidence
High

## Location
`app/lib/data/debug/debug_log_impl.dart:47`

## Issue
The detailed `File-backed DebugLog` dartdoc is attached to the private `_DebugLogFailure` enum immediately above it, leaving the public `DebugLogImpl` service without native documentation for its snapshot, flush, failure, and lifecycle contract in IDE and agent surfaces.

## Fix
Move or duplicate the intent-bearing dartdoc so it directly precedes `DebugLogImpl`, leaving only enum-specific documentation on `_DebugLogFailure`.
