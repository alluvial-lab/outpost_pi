---
id: gate-tests-app-relay-ingress-boundaries
kind: story
stage: review
tags: [testing]
parent: null
depends_on: []
release_binding: v0.2.0
gate_origin: tests
created: 2026-07-20
updated: 2026-07-20
---

# Add regression coverage for the app's bounded relay-ingress decoder

## Priority

High

## Value evidence

Item: `feature-typed-bounded-relay-decoding`

Contract / risk / regression / maintenance cost: the release's cross-stack security feature requires the app to reject raw input before JSON parsing, reject encoded payloads before base64 decode, check decoded length, return deterministic rejection categories, and prevent multibyte input from bypassing the UTF-8 byte ceiling (`.work/active/features/feature-typed-bounded-relay-decoding.md:399-407`). Its testing plan explicitly calls for small injected-limit raw, multibyte, encoded, and decoded cases at line 492.

Those decisions are implemented in `app/lib/data/transport/relay_frame_decoder.dart:52-73` and `:77-124`, with the base64 boundary at `:175-217`, but the only direct demux tests (`app/test/data/transport/ws_transport_demux_test.dart:11-79`) cover matching/missing/mismatched rooms, one control frame, and malformed JSON. No current app test calls the injected `maxRawBytes` or `maxDecodedPayloadBytes` seams, exercises multibyte input, checks exact/over base64 boundaries, or tests the bounded pre-auth challenge decoder. A regression in rejection ordering or byte accounting could therefore restore the app-side allocation/DoS risk while the suite remains green.

## Gap type

important-interface / bug-regression — missing boundary-value and equivalence-partition coverage for a security-sensitive untrusted-input decoder.

## Suggested test

```dart
group('bounded relay ingress', () {
  test('multibyte raw input crosses the UTF-8 limit before JSON parsing', () {
    final result = decodeRelayInboundFrame('é{', maxRawBytes: 2);
    expect(result, isA<RejectedRelayFrame>()
      .having((r) => r.reason, 'reason', RelayFrameDecodeFailure.tooLarge));
  });

  test('accepts the exact decoded boundary and rejects the next payload', () {
    // Build valid typed outer frames with small injected limits; assert the
    // exact payload decodes and the next base64 quantum is rejected as tooLarge.
  });

  test('pre-auth challenge requires a bounded canonical 32-byte nonce', () {
    // Cover raw oversize, malformed/wrong frame, 31/33-byte nonce, and success.
  });
});
```

Keep the fixtures small through injected limits; do not allocate multi-megabyte strings or duplicate generated DTO validation.

## Test location (suggested)

`app/test/data/transport/relay_frame_decoder_test.dart` (new), with only transport-routing assertions remaining in `app/test/data/transport/ws_transport_demux_test.dart`.

## Gate run context

The operator required the test scanner to run inline with no nested sub-agent. This finding therefore has reduced fresh-context isolation. It was verified directly against the release-bound acceptance contract, decoder implementation, and current app transport tests.

## Implementation notes

- **Execution capability:** inline focused test addition; the decoder already exposed deterministic injected-limit seams, so no production refactor or coordination was needed.
- **Files changed:** `app/test/data/transport/relay_frame_decoder_test.dart` (new).
- **Coverage added:** UTF-8 multibyte raw-byte rejection before JSON parsing; exact decoded acceptance; encoded pre-decode rejection; decoded post-decode rejection; pre-auth raw ceiling; wrong challenge type; 31/32/33-byte nonce behavior.
- **Confirmation:** the new test file passed (6 tests), `flutter analyze` passed, and the complete non-e2e Flutter suite passed (792 tests). The repository-wide `flutter test` command additionally discovered four integration tests that require pairing harness endpoints; those failed only because the runner environment variables were absent.
- **Bounded inline review:** pass — fixtures use injected one-to-three-byte limits except the canonical 16 KiB pre-auth ceiling check, assert deterministic categories/sizes, and exercise production decoders rather than mirrored logic.
- **Adjacent issues parked:** none.
