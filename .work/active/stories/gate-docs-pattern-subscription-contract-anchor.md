---
id: gate-docs-pattern-subscription-contract-anchor
kind: story
stage: implementing
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

## Required edit
Replace the example and line anchor with the current decoded-ingress handler-set contract.
