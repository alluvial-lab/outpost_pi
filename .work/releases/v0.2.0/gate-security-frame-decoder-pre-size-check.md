---
kind: story
release_binding: v0.2.0
parent: feature-typed-bounded-relay-decoding
stage: done
id: gate-security-frame-decoder-pre-size-check
tags: [security]
depends_on: []
gate_origin: security
created: 2026-07-01
updated: 2026-07-20
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

## Implementation notes
- Execution capability: `openai-codex/gpt-5.6-sol` (caller-selected for security-critical relay work).
- Review weight: `standard` (caller default; feature-level review only).
- Files changed: `relay/src/protocol/frame.rs`, `relay/src/protocol/outer.rs`.
- Tests added: injected-limit regressions prove raw oversize precedes malformed JSON and decoded-equivalent base64 boundaries remain enforced.
- Simplification: one decoder now owns the raw-before-parse ordering and production size derivation.
- Discrepancies from design: canonical cross-stack generation is outside this relay-only worker's write scope; the relay-owned boundary uses the existing configured decoded limit and derived overhead locally pending the cross-stack owner.
- Adjacent issues parked: none.
- Verification: focused protocol-frame tests passed after the size-ordering regression was updated to distinguish raw and decoded ceilings.
