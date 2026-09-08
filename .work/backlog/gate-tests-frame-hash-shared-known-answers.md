---
id: gate-tests-frame-hash-shared-known-answers
created: 2026-09-07
updated: 2026-09-07
tags: [testing, app, relay]
release_binding: null
gate_origin: tests
---

# Pin paired frame hashes with shared independent known answers

## Priority
Medium — non-blocking backlog per `gate_finding_routing`.

## Value evidence
Targeted v0.12.0 rc.2 gate over `3a06ebb1a` and `49180245a`.
Item: `story-metronome-paired-frame-hash-instrument`.
The instrument's diagnostic value depends on Rust outbound and Dart inbound
producing identical per-message and running hashes for identical bytes and
message indices. A disagreement would misdirect corruption attribution.

`relay/src/handlers/peer.rs:650-673` pins the real FNV result for UTF-8 `hé`
and verifies the counter, but derives the expected running value by calling
the same production `fold_running_hash` used by `observe`. Changing that
fold to big-endian, for example, would leave this test green.

`app/test/data/transport/ws_transport_close_diagnostics_test.dart:16-18`
pins `hello` on a test-only helper. The real transport is usefully exercised
at lines 119-156 against independent test-helper calculations for challenge
and presence messages, including indices/count and final hash. However, its
running-fold oracle at lines 451-465 mirrors the Dart implementation, and
neither endpoint consumes the same fixed running-hash answers. The Rust and
Dart vectors differ. Same-basis compatibility is documented, not jointly
pinned by a shared known-answer contract.

These are not dishonest tests: the actual transport and counter assertions
provide value. Preserve them and strengthen the cross-language seam rather
than deleting them or demanding universal unit coverage.

## Gap type
Cross-language diagnostic seam / independent running-fold oracle.

## Suggested test
Check in a small independently calculated byte-vector table, consumed by both
endpoints' production instrument paths. Include exact UTF-8 bytes, a high-bit
hash, successive one-based indices, and fixed per-frame/running hashes. Assert
zero-state offset and control-frame exclusion without recomputing expected
running values through production helpers.

Example independently calculated Python integer/`struct.pack('<QQ', ...)`
answers for text messages `hé`, then `second`:

| Index | Frame hash | Running hash |
| --- | --- | --- |
| 1 | `3130f1192e1ad66f` | `c4cd5692c2735e08` |
| 2 | `a49985ef4cee20bd` | `246e72931154c92c` |

Use valid protocol messages when driving the real Dart handshake, or establish
a narrow production instrument test seam; do not merely test another helper.
Prove that a one-sided fold-endianness or basis mutation fails the fixture.

## Suggested locations
- `protocol/fixtures/` (shared diagnostic known-answer fixture)
- `relay/src/handlers/peer.rs` test module
- `app/test/data/transport/ws_transport_close_diagnostics_test.dart`

## Gate verification
Source-read-only analysis; no product source edits or suite execution. A small
standalone Python calculation independently checked the example values above.
