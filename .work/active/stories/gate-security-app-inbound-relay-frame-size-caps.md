---
kind: story
release_binding: null
parent: feature-typed-bounded-relay-decoding
stage: done
id: gate-security-app-inbound-relay-frame-size-caps
tags: [security]
depends_on: []
gate_origin: security
created: 2026-07-01
updated: 2026-07-18
---

# Mobile app decodes inbound relay frames before size caps

## Severity
Low

## Domain
Input Validation & Injection / API Security / Error Handling

## Location
`app/lib/data/transport/ws_transport.dart:304`

## Evidence
```dart
final frame = jsonDecode(raw) as Map<String, dynamic>;

// Envelope: {peer, ct} with room-aware routing.
if (frame.containsKey('peer') && frame.containsKey('ct')) {
  final bytes = _b64Decode(frame['ct'] as String);
```

## Issue
The mobile WebSocket demux parses the whole relay frame and base64-decodes `ct` before enforcing any explicit raw-frame or decoded-payload size cap. A malicious/compromised relay or sender that can get a frame delivered to the app can force avoidable allocation and decode work up to the WebSocket stack's implicit limits. Provenance: introduced in this bundle's app transport refactor (`git blame` points at the v0.6.0-bound app relay demux change).

## Remediation direction
Add explicit raw-frame and decoded-payload limits before `jsonDecode` / `_b64Decode`, align the cap with the protocol's relay envelope limit, and surface/drop oversized frames through the existing malformed-frame path without logging payload content.

## Implementation notes
- Execution capability: `openai-codex/gpt-5.6-sol` (caller-selected for security-critical cross-stack boundary work).
- Review weight: `standard` (caller-provided; feature-level review only).
- Files changed: `app/lib/data/transport/relay_frame_decoder.dart` and `ws_transport.dart`.
- Tests added/updated: no test files changed because the caller restricted app writes to `app/lib/data/transport/**`; the existing five demux tests and auth-vector test pass, and the decoder exposes injected limits for focused boundary coverage.
- Simplification: challenge parsing moved behind the same typed boundary; WebSocket transport no longer parses a pre-auth map or logs attacker-controlled decode exception text.
- Discrepancies from design: Flutter still cannot configure a native WebSocket `maxPayload`; this bounds UTF-8 scanning, JSON, and base64 work after the platform materializes the String. Endpoint constants match the canonical schema value and TypeScript derivation, but Dart codegen does not project relay limit metadata and codegen paths were outside allowed scope.
- Adjacent issues parked: none.
- Verification: six focused app demux/auth tests passed.
