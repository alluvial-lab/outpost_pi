---
id: story-pairing-flow-single-frame-read-race
kind: story
stage: done
tags: [bug, app]
parent: null
depends_on: []
release_binding: app-v0.3.0
gate_origin: null
created: 2026-07-27
updated: 2026-07-27
---

# Pairing flow crashes when channel traffic races the pair_ok reply

## Reproduction
Live (2026-07-26/27, phone with a large offline backlog on the extension):
`/outpost-pi pair` → scan → app throws
`FormatException: Unexpected extension byte (at offset 1)`. First attempt at
17:41 hit it, second dodged it; 2026-07-27 attempt hit it again — timing
dependent.

## Root cause
`app/lib/pairing/pair_request_flow.dart:165-166` reads exactly ONE frame
after sending `pair_request` and unconditionally `utf8.decode`s it as JSON.
When the extension's backlog flush (or any other channel traffic) beats the
`pair_ok` to the app's pairing transport, the frame is sealed ciphertext —
`utf8.decode` throws `FormatException`, the pairing flow dies unhandled, the
extension has already persisted its side, and the app is left half-paired.

## Fix
Read frames in a bounded loop until the `pair_ok`/`pair_error` reply with
matching `in_reply_to` arrives; skip undecodable frames (sealed traffic) and
frames replying to other ids. The existing outer 45s timeout bounds the loop.

## Acceptance
- A pairing whose transport delivers a sealed/garbage frame and an unrelated
  JSON frame before `pair_ok` completes successfully.
- A `pair_error` reply still surfaces with its code.
- The unhandled-FormatException path is gone (decode failures are skipped,
  never thrown raw).

## Implementation notes
`performPairing` now reads frames in a loop until the `pair_ok`/`pair_error`
reply with matching `in_reply_to` arrives: undecodable frames (sealed
channel traffic racing the handshake) and replies to other ids are skipped;
a zero-length frame (closed-transport drain) throws
`PairingError(code: transport_closed)` instead of busy-looping — the second
form was caught by the pre-existing
`pairing_viewmodel` stale-persistence test, which hung 2:55 on the first
loop version. Regression tests: garbage+unrelated frames before `pair_ok`
complete the pairing; garbage before `pair_error` surfaces the typed code.
Verification: flutter analyze clean; full non-e2e suite 849/849 (1m25s).

## Review
Bounded inline review (orchestrator, 2026-07-27): fix is minimal and at the
right boundary (handshake read loop); skipped frames are safe to drop (the
post-attach channel replays idempotently on session_sync); empty-frame
guard prevents the closed-transport spin. Approved -> done.
