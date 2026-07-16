---
id: feature-typed-bounded-relay-decoding
kind: feature
stage: drafting
tags: [app, pi-extension, relay, security, protocol]
parent: null
depends_on: []
release_binding: null
gate_origin: security
created: 2026-07-15
updated: 2026-07-16
---

# Cross-stack: typed and size-bounded inbound relay/WebSocket decoding

## Brief

Five gate findings (one refactor, four security) describe the inbound
relay/WS decode path across all three stacks: untrusted frames are parsed as
full JSON strings and their `ct` payloads are base64-decoded **before** any
explicit raw-frame or decoded-payload size cap runs, and the post-auth demux
navigates the parsed map by hand. This is a cross-stack DoS vector
(unbounded parse before size check) and an ad-hoc-parse-at-a-boundary defect.
This feature defines typed, size-bounded decoding at the WS/relay boundary:

- `gate-refactor-boundaries-demux-adhoc-map` — WebSocket post-auth demux parses frames through an ad-hoc map
- `gate-security-app-inbound-relay-frame-size-caps` — mobile app decodes inbound relay frames before size caps
- `gate-security-extension-inbound-relay-frame-size-caps` — pi extension decodes inbound relay frames before size caps
- `gate-security-frame-decoder-pre-size-check` — frame decoder parses JSON before applying relay-owned size checks
- `gate-security-preauth-websocket-size-limits` — pre-auth WebSocket frames and hello metadata lack explicit size limits

## Simplification opportunity

Enforce explicit WebSocket frame/message ceilings before upgrade, add bounded
lengths for pre-auth `device_id`/`room_id`/room-metadata strings, and run size
checks before full JSON parse + base64 decode. Type the demux through generated
frame DTOs. Behavior change: oversize/malformed frames are rejected at the
boundary instead of parsed — fail-fast, not silent.

## Source

Promoted from backlog by `scope` (2026-07-15). 1 `gate-refactor-boundaries-*`
+ 4 `gate-security-*-frame-size-*` / `gate-security-preauth-*` findings from
the v0.6.0 release `gate-refactor` (boundaries) and `gate-security` passes.
