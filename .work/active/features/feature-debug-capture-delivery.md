---
id: feature-debug-capture-delivery
kind: feature
stage: implementing
tags: [app, pi-extension, ux]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-24
updated: 2026-08-24
---

# Deliver app debug captures directly to the paired Pi session

Operator ask (2026-08-24): replace the export→workstation→scp→repo `debug/`
loop with in-app delivery of debug capture rings to the paired session over
the existing sealed owner channel. Today every triage costs minutes of
manual transfer; the phone already holds an authenticated AEAD channel to
the exact place the captures are triaged.

## Design (locked)

- **Contract-first**: extend `protocol/schema/outpost-pi.schema.json`
  (single source; regenerate Dart + TS via tools/protocol-codegen). New
  message family for chunked upload: begin (upload id, device label, total
  bytes, capture kind) / chunk (sequence, base64 payload, bounded) / end
  (checksum) with ack + typed errors (too_large, bad_sequence, io_error).
  Explicit caps: chunk ≤ 8 KiB decoded, total ≤ 2 MiB, in-flight uploads
  per session ≤ 1; abandoned uploads GC'd on a timer and on detach.
- **Extension handler** (pi-extension/src/actions or sibling): reassemble,
  validate NDJSON-ish sanity + caps, write ATOMICALLY (tmp+rename) to the
  room cwd's `debug/` directory as `app-capture-<iso8601>-<idtail>.bin`.
  Path containment guard (no traversal outside `<cwd>/debug/`), size
  enforced before write. On success: ack with the written path AND surface
  a session-visible system note (e.g. "Debug capture delivered:
  debug/…bin (N events, M KB) from <device>") so the orchestrator session
  sees the delivery arrive without polling.
- **App**: "Send debug logs" quick action in the chat quick-actions sheet:
  picks the latest closed capture ring (or snapshots the active ring),
  streams chunks with progress + delivered/failed state; errors surface in
  the sheet (retry). No chat-transcript pollution (control family, not
  user messages).
- **Relay untouched** (`ct` opaque). Sealed-channel confidentiality already
  applies; the payload is the operator's own device log.

## Stories

1. `story-capture-delivery-protocol-extension` — schema + codegen +
   extension handler + unit tests (reassembly, caps, traversal guard,
   atomic write, GC, note surface).
2. `story-capture-delivery-app-upload` — quick action + upload client +
   progress/error UX + widget tests with fake transport (chunking,
   resume-free retry from scratch, failure paths).
3. `story-capture-delivery-e2e` — live two-side scenario: harness-paired
   app delivers a synthetic ring; assert file lands in room cwd `debug/`,
   note surfaces, and `scripts/debug_capture_triage.py` parses the
   delivered file clean; runner selector wired.

## Verification

Per-story suites; live e2e green on the device lane; fold golden matrix
unaffected (quick-actions sheet gains one row — regenerate). Ship: app
0.7.0+12 APK + extension dist refresh (full agent restart via
scripts/refresh-dist.sh semantics).

## Review record

Filled at completion.
