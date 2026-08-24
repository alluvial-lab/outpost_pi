---
id: gate-docs-flutter-mobile-ping-interval
kind: story
stage: done
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: docs
created: 2026-08-24
updated: 2026-08-25
---

# Flutter mobile skill documents the obsolete WebSocket ping interval

## Drift category
repo-skill-staleness

## Location
- Doc: `.agents/skills/flutter-mobile/SKILL.md:179-185`
- Contradicting source: `app/lib/data/transport/ws_transport.dart:138-140`

## Current doc text
> `WsTransport` uses `IOWebSocketChannel.connect(..., pingInterval: 20s)` for app↔relay TCP liveness.

## Contradiction
The current `WsTransport` constructs the channel with a 45-second
`pingInterval`. The 20-second value is no longer a valid transport fact for
agents using this reference.

## Required edit
Replace the 20-second claim with the current 45-second WebSocket interval and
keep the separate Pi-liveness protocol-ping distinction intact.

## Implementation

Updated the transport reference to the 45-second app↔relay WebSocket interval while retaining the separate Pi protocol-ping distinction in `.agents/skills/flutter-mobile/SKILL.md`.
