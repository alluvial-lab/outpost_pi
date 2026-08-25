---
id: gate-docs-pattern-owner-channel-loss-anchor-v080
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

# Owner-channel resource pattern points at pre-hedge connection-loss code

## Drift category
pattern-skill-staleness

## Location
- Doc: `.agents/skills/patterns/owner-channel-scoped-resource-ownership.md:69-87`
- Contradicting source: `app/lib/data/transport/connection_manager.dart:1847-1891`

## Current doc text
> Connection loss acts only on the active channel instance — `connection_manager.dart:1584-1623`.

## Contradiction
The reconnect-hedge changes moved `_onChannelLost` to lines 1847-1891 and added cause attribution plus the persistent hedge flag. The cited range now points at unrelated room-cache code, so the pattern no longer demonstrates the active-channel identity guard or current teardown/retry behavior.

## Required edit
Refresh the anchor and snippet to the current `_onChannelLost` implementation, including the identity check and hedge scheduling behavior, while preserving the owner/channel-scoped resource rule.

## Implementation
- Updated the active-channel identity and hedge teardown example in `.agents/skills/patterns/owner-channel-scoped-resource-ownership.md`.
