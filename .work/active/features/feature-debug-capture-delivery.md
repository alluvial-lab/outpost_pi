---
id: feature-debug-capture-delivery
kind: feature
stage: done
tags: [app, pi-extension, ux]
parent: null
depends_on: []
release_binding: v0.7.0
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

## Review record (2026-08-24)

**Standard weight, one independent fresh-context pass** (gpt-5.6-sol).
Verdict: Request changes → **closed done** after receiver-confirmed closure
in 28d56bfe (standard policy, no second pass).

- **Blockers (3/3 fixed+verified):** symlinked `debug/` escaped lexical
  containment (now lstat-rejected + realpath-verified); in-flight slot
  released before async commit + per-chunk Buffer retention (now held
  through commit, single preallocated declared-total buffer); delivery
  note sent `triggerTurn:false` so an idle orchestrator never woke (now
  true — the feature's core promise).
- **Important (2):** upload cleanup was global-not-owned and leaked on
  relay-wide loss (now owner+channel-scoped, fresh begin after reconnect
  succeeds); schema `maxInFlight`/cap constants generated but not consumed
  (now imported both sides).
- **Rejected (6):** upload-id traversal, checksum/atomicity, e2e stub,
  triage cosmetic, golden regressions, relay/plaintext/cockpit drift —
  all upheld on inspection.
- Post-fix: 1022 extension + 918 app tests, live capture-delivery e2e
  green end-to-end, goldens unchanged.
- Shipped: app 0.7.0+12, pi-extension 0.2.0.
