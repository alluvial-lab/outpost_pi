---
kind: story
release_binding: null
parent: feature-typed-bounded-relay-decoding
stage: done
id: gate-refactor-boundaries-demux-adhoc-map
tags: []
depends_on: []
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-18
---

# WebSocket post-auth demux parses frames through an ad-hoc map

## Library
boundaries

## Rule
ad-hoc-wire-parse

## Confidence
Medium

## Location
app/lib/data/transport/ws_transport.dart:287

## Issue
demuxPostAuthInboundFrame decodes untrusted WS frames as Map<String, dynamic> and manually navigates peer, ct, room, type. No Dart generated DTO covers this top-level relay frame — a typed-boundary gap.

## Fix
needs analysis: add a typed DTO for the top-level relay frame

## Implementation notes
- Execution capability: `openai-codex/gpt-5.6-sol` (caller-selected for security-critical cross-stack boundary work).
- Review weight: `standard` (caller-provided; feature-level review only).
- Files changed: `pi-extension/src/protocol/relay_ingress.ts`, its focused test, the extension relay/owner/peer/cross-PC consumers, `app/lib/data/transport/relay_frame_decoder.dart`, and `ws_transport.dart`.
- Tests added/updated: one shared TypeScript ingress boundary suite; relay transport tests now assert typed one-owner dispatch. The existing Dart demux suite verifies unchanged outer/control routing.
- Simplification: removed source-local JSON/base64 parsers from extension owner, peer-channel, relay-control, and cross-PC paths; `ws_transport.dart` no longer navigates relay maps.
- Discrepancies from design: Rust already dispatches generated `RelayInboundFrame` DTOs from the completed relay checkpoints. TypeScript validators return generated relay-control/cross-PC DTOs, but the canonical generator does not emit a TS outer DTO. Dart codegen emits no relay DTO family and this worker's write scope excludes schema/codegen/app protocol outputs, so the app uses one transport-local sealed DTO adapter rather than another map parser. These constrained handwritten outer adapters remain candidates for later generator projection.
- Adjacent issues parked: none.
- Verification: pi-extension TypeScript check passed; 69 focused extension ingress/transport/owner/cross-PC tests passed; 5 app demux tests passed.
