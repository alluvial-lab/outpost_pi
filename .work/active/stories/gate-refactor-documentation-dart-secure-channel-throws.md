---
id: gate-refactor-documentation-dart-secure-channel-throws
kind: story
stage: review
tags: [refactor]
parent: null
depends_on: []
release_binding: v0.3.0
gate_origin: refactor
created: 2026-07-24
updated: 2026-07-24
---

# Dart owner-channel helpers omit their throwing contracts

## Library
documentation

## Rule
error-path

## Confidence
High

## Location
`app/lib/data/transport/secure_channel.dart:95`

## Issue
Exported cryptographic helpers explicitly throw for invalid key lengths, low-order keys, sequences, and nonces, but their dartdoc does not describe those failures.

## Fix
Add `Throws [ArgumentError]` and `Throws [RangeError]` contract notes to the affected derivation, transcript, proof, and sealing helpers.

## Implementation notes
- Documented the invalid-length, low-order-key, and sequence-range failure contracts on the public derivation, proof, transcript, and sealing helpers.
- Verification: `cd app && flutter test test/data/transport/secure_channel_test.dart` (passed).
