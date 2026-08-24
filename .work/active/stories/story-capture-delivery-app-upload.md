---
id: story-capture-delivery-app-upload
kind: story
stage: done
tags: [app]
parent: feature-debug-capture-delivery
depends_on: ['story-capture-delivery-protocol-extension']
release_binding: null
gate_origin: null
created: 2026-08-24
updated: 2026-08-26
---

# Capture upload: app quick action + chunked upload client + progress UX

Per feature design. "Send debug logs" row in quick-actions (icon+label per
Phosphor tokens; 48dp hit region; regenerate the quick-actions goldens).
Client: reads latest closed ring (fallback: snapshot active ring), base64
chunks ≤8 KiB decoded, begin/chunk/end per generated protocol, progress
(0-100, indeterminate while reading), delivered state shows the ack'd path,
retry restarts from scratch (no resume v1), typed error surfacing. Widget
tests with fake transport: chunk sequencing, mid-chunk failure → retry
works, oversize ring → friendly refusal, delivered state. `flutter
analyze` + full suite green.

## Implementation

- Added a domain upload port and data adapter that snapshots the current debug
  ring, refuses empty/oversize captures, streams schema-sized base64 chunks,
  correlates typed acknowledgements/errors, verifies monotonic acknowledgements,
  and restarts retries with a fresh upload id at sequence zero.
- Added the `Send debug logs` quick-action row with reading, percentage,
  delivered-path, and retryable error states; capture control replies remain
  outside transcript projection.
- Added fake-channel tests for chunk sizing/sequencing, progress, oversize
  refusal, mid-chunk failure, and resume-free retry, plus widget coverage for
  delivered and retry UX.
- Verification: `flutter analyze` and `flutter test --exclude-tags e2e
  --concurrency=2` pass from `app/`.

## Review closure

- Confirmed the app uploader consumes the generated Dart chunk and total-byte
  ceilings; no app-visible row or golden changed during receiver hardening.
- Re-ran `flutter analyze` and the full non-e2e suite with concurrency 2: all
  918 tests pass.
