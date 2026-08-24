---
id: gate-refactor-lifecycle-capture-upload-runtime
kind: story
stage: done
tags: []
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: refactor
created: 2026-08-24
updated: 2026-08-25
---

# Fence capture finalization and its timer to the owning runtime

## Library
lifecycle

## Rule
resource-no-dispose

## Confidence
High

## Location
`pi-extension/src/index.ts:579`

## Issue
The process-global `CaptureUploadHandler` owns an interval but no runtime teardown calls `dispose`; teardown only calls `detachAll`, and an `end()` already awaiting `commit` at `pi-extension/src/actions/capture_upload_handler.ts:228` still writes the file, emits the delivered note, and attempts the ACK after its owner channel or Pi session has detached.

## Fix
Give the handler explicit runtime-epoch ownership: dispose/recreate its timer at the matching lifecycle boundary and fence post-commit note/ACK side effects against owner-channel and session replacement while preserving atomic cleanup.

## Implementation
- Execution capability: `sol/high` (caller-selected for lifecycle-sensitive async work).
- The active extension epoch now disposes the capture handler during `prepareSessionShutdown` and replaces it only after the successor epoch binds its API, so the stale-upload interval cannot outlive runtime ownership.
- Handler disposal is idempotent and invalidates the active upload. A finalization already awaiting its serialized disk commit may finish atomic file cleanup, but it cannot emit a stale Pi note, ACK, or error after detach/disposal.
- Added an explicit deferred-commit regression test that disposes at the vulnerable boundary and proves the file lands atomically while post-commit note/reply side effects remain suppressed.
- Verification: capture-upload suite 16/16 pass.
- Adjacent issues parked: none.
