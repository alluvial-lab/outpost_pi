---
id: gate-docs-pattern-subscription-contract-anchor
kind: story
stage: done
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.3.0
gate_origin: docs
created: 2026-07-24
updated: 2026-07-24
---

# Subscription pattern shows the obsolete relay-listener registration contract

## Drift category
pattern-skill-staleness

## Location
- Doc: `.agents/skills/patterns/subscription-unsubscribe-contract.md:54-66`
- Contradicting source: `pi-extension/src/extension/relay_transport.ts:567-576`

## Current doc text
> Example shows relay?.on("message", handler) via onOuterMessage.

## Contradiction
onOuterMessage now subscribes handlers to decoded outer ingress plus a generation predicate. The relay transport centrally owns the raw listener and decode/dispatch FIFO; subscribers no longer register directly on RelayClient.

## Implementation notes

Replaced the obsolete raw RelayClient listener example with the current decoded-ingress handler-set subscription contract at `relay_transport.ts:567-577`.

## Required edit
Replace the example and line anchor with the current decoded-ingress handler-set contract.

## Review

Bounded inline review (orchestrator, 2026-07-24): refreshed anchors and
quoted snippets verified line-by-line against current sources
(mesh_sync_service.dart:300, sdk_session_projection.ts:678/695/906,
relay_transport.ts:567-577, relay_ingress.ts:81). Approved -> done.
