---
id: gate-patterns-inconsistency-pair-request-flow-typed-decoder
kind: story
stage: done
tags: [refactor, app]
parent: null
depends_on: []
release_binding: v0.4.0
gate_origin: patterns
created: 2026-07-24
updated: 2026-08-11
---

# pair_request_flow decodes the untrusted pairing response with raw jsonDecode

## Existing pattern
`typed-wire-decoders`

## Divergent code
`app/lib/pairing/pair_request_flow.dart:162-167`

## Nature of divergence
The untrusted pairing response is decoded through raw jsonDecode, cast to Map<String, dynamic>, and manually dispatched by type instead of entering through the shared typed server-message decoder.

## Reconciliation direction
Bring the code into conformance with the documented pattern (or, if the
divergence is deliberate, amend the pattern's "When NOT to Use"). Routed to a
subsequent release — parked unbound by gate-patterns for v0.3.0.

## Implementation note
Route the pairing response through the shared typed server-message decoder
(`app/lib/protocol/...`) instead of raw `jsonDecode` + manual `Map<String,
dynamic>` dispatch at `pair_request_flow.dart:162-167`. The `pair_ok`/
`pair_error` discriminators already exist in the generated server-message
registry; consume them. If the pairing response is a genuine protocol island
(distinct from server messages), amend the `typed-wire-decoders` pattern's
"When NOT to Use" with the rationale rather than forcing it through. Black-box
preserving: the decoded result must not change for valid responses.

## Implementation notes

- Added `decodeServerFrame`, the shared generated server-message decoder with the wire-presence metadata pairing needs for legacy `room_id` fallback.
- Pairing now filters typed `PairOk`/`PairError` responses and no longer parses or dispatches a raw JSON map.
- Existing pairing tests preserve valid `pair_ok`, legacy missing-`room_id`, and `pair_error` outcomes.
- Verification: `flutter test test/pairing/pair_request_flow_test.dart --concurrency=2` (9 passing).
