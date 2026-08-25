---
id: gate-docs-pattern-frame-byte-admission-anchor-v080
kind: story
stage: done
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.8.0
gate_origin: docs
created: 2026-08-25
updated: 2026-08-25
---

# Frame-byte pattern points at the wrong WebSocket queue lines

## Drift category
pattern-skill-staleness

## Location
- Doc: `.agents/skills/patterns/frame-byte-bounded-admission.md:10-25`
- Contradicting source: `app/lib/data/transport/ws_transport.dart:646-658`

## Current doc text
> App WebSocket inbound FIFO example — `app/lib/data/transport/ws_transport.dart:572-584`.

## Contradiction
The v0.8 transport changes moved `WsInboundMessageQueue.add` to lines 646-658. The cited range is the post-auth demux implementation and does not show dual frame/byte admission or pending-byte accounting.

## Required edit
Refresh the pattern anchor and snippet to the current `WsInboundMessageQueue.add` implementation at `ws_transport.dart:646-658`.

## Implementation
- Updated the frame/byte admission pattern to the current `WsInboundMessageQueue.add` anchor in `.agents/skills/patterns/frame-byte-bounded-admission.md`.
