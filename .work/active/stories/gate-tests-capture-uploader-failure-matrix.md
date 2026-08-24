---
id: gate-tests-capture-uploader-failure-matrix
kind: story
stage: implementing
tags: [testing, app]
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: tests
created: 2026-08-24
updated: 2026-08-24
---

# Cover capture-upload transport loss, deadlines, and malformed acknowledgements

## Priority
High

## Value evidence
Item: `story-capture-delivery-app-upload`. The feature promises typed failure
surfacing and a retry that restarts from scratch. The uploader has distinct
branches for correlated wrong-stage ACKs, channel error/done, reply timeout,
send failure, wrong chunk sequence, and delivered ACKs without a path
(`app/lib/data/debug/debug_capture_uploader.dart:154-232`). Its tests cover only
happy-path chunking, one typed mid-chunk `io_error`, and preflight oversize
refusal (`app/test/data/debug/debug_capture_uploader_test.dart:141-240`). A real
mobile reconnect can close or replace the captured channel at any upload stage;
that release-critical failure seam is not protected.

## Gap type
important-interface / unavailable-dependency / interrupted-operation

## Suggested test
```dart
// Table-drive a controllable IChannel through:
// - send() throws before ACK -> send_failed;
// - stream error/done after begin or a chunk -> disconnected, no end frame;
// - no correlated reply before the injected deadline -> timeout;
// - correlated wrong stage/next_sequence and delivered-without-path -> the
//   documented typed failure.
// Then replace ConnectionManager.channel and retry: assert a fresh upload_id,
// current session_id, new begin, and first chunk sequence 0 on the new channel.
// Unrelated request/upload ACKs must be ignored, not complete the upload.
```

## Test location (suggested)
`app/test/data/debug/debug_capture_uploader_test.dart`
