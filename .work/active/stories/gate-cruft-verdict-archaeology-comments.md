---
id: gate-cruft-verdict-archaeology-comments
kind: story
stage: done
tags: [cleanup]
parent: null
depends_on: []
release_binding: null
gate_origin: cruft
created: 2026-10-04
updated: 2026-10-05
---

# Transport comments retain transient verdict and .work archaeology

## Confidence
Medium

## Category
Stale comment / plan-era prose

## Location
`app/lib/data/transport/connection_manager.dart:756-763`;
`app/lib/data/transport/ws_transport.dart:261-264,726-729`;
`app/lib/domain/value_objects/reachability.dart:17-22,52-57`;
`app/test/data/transport/ws_transport_close_diagnostics_test.dart:139-144,191-193`

## Evidence
Comments cite verdict numbers, field-count narratives ("5/5 strikes"),
outage-duration claims, and `.work` story links — transient work state
referenced from durable code. Repo convention: code references logical
concepts, not tracking IDs.

## Removal
Trim to concise current-state rationale: WHY handshake-stall classification
and synthetic-close attribution exist (zero-inbound wedged path; dart
synthesizes 1002/1001), without the incident narrative. (The
connection-manager header block is handled in
`gate-cruft-ping-miss-threshold-comment`.)

## Implementation notes (2026-10-05)

- Seven sites trimmed to current-state rationale (reachability ×2,
  ws_transport ×2, connection_manager ×1, close-diagnostics test ×2):
  verdict numbers, strike counts, outage durations, .work links removed;
  the WHY (zero-inbound wedge class, dart-synthesized 1002/1001
  attribution) preserved.