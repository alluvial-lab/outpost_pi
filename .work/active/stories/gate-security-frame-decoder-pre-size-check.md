---
kind: story
release_binding: null
parent: feature-typed-bounded-relay-decoding
stage: drafting
id: gate-security-frame-decoder-pre-size-check
tags: [security]
depends_on: []
gate_origin: security
created: 2026-07-01
updated: 2026-07-01
---

# Frame decoder parses JSON before applying relay-owned size checks

## Severity
Low

## Location
relay/src/protocol/frame.rs:38

## Issue
decode_relay_frame deserializes the full inbound text into serde_json::Value before outer-envelope size checks run, so oversized typed frames or malformed envelopes can force avoidable allocation/parse work.

## Recommendation
Reject inbound text.len() above a configured raw frame cap before JSON parsing and align the WebSocket max message size with relay payload limits.
