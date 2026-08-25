---
id: gate-cruft-ws-transport-post-rollback-comment
kind: story
stage: done
tags: [cleanup]
parent: null
depends_on: []
release_binding: v0.8.0
gate_origin: cruft
created: 2026-08-25
updated: 2026-08-25
---

# Remove the stale post-rollback plaintext claim from the app transport comment

## Confidence
High

## Category
Stale comment

## Relevance
Release-relevant: the transport file was changed by the reconnect-hedge delta.

## Location
`app/lib/data/transport/ws_transport.dart:10-13`

## Evidence
```dart
// `peer` is standard base64 of the destination's Ed25519 pubkey (matches
// the relay registry, populated from the peer's hello). `ct` is base64 of
// the inner-envelope bytes (plain JSON post-rollback, see plan 06).
```

Current owner-channel traffic passes sealed XChaCha20-Poly1305 frame bytes through `ct`; the active transport also validates the post-auth encrypted/typed boundary. The comment describes the retired plaintext frame shape.

## Removal rationale
Replace the historical `plain JSON post-rollback, see plan 06` wording with the current description that `ct` carries opaque base64 owner-channel frame bytes. Remove the obsolete plan-era claim rather than preserving contradictory protocol archaeology.

## Risk
None to behavior. This is a documentation-only correction; the relay remains opaque to `ct`.

## Implementation
- Proof: `PROTOCOL.md` defines post-pairing `outer.ct` as an opaque owner-channel E2E sealed frame, and the app transport passes `ct` through without interpreting plaintext; grep found the rollback-era phrase only in this header.
- Removal: replaced the plaintext/plan-era claim with the current opaque, base64-encoded owner-channel frame description.
- Verification: `flutter analyze lib/data/transport/ws_transport.dart` passed with no issues. The release-wide app analyze and full non-E2E suite are recorded in the gate-fix completion report.
- Execution capability: sol/high; direct-read documentation cleanup verified against the canonical protocol.
- Adjacent issues parked: none.
