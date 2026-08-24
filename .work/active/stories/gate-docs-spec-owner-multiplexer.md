---
id: gate-docs-spec-owner-multiplexer
kind: story
stage: implementing
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: docs
created: 2026-08-24
updated: 2026-08-24
---

# SPEC describes the obsolete singleton owner channel

## Drift category
foundation-doc-assertion

## Location
- Doc: `docs/SPEC.md:173-179`
- Contradicting source: `pi-extension/src/extension/owner_multiplexer.ts:202-212` and `docs/DECISIONS.md:78-81`

## Current doc text
> `_peerChannel` is a singleton in the extension; broadcast happens at the relay.
> Resolved — the runtime invariant is "1 active connection per `(peer, room)` at the extension, broadcast-fanout at the relay."

## Contradiction
The current extension owns an `OwnerMultiplexer` with a channel map keyed by
owner peer, and its runtime routes/fanouts per owner channel. The old
`_peerChannel`/relay-broadcast description is not the current implementation and
contradicts the current one-generation-per-owner decision.

## Required edit
Rewrite this resolved ambiguity in place to describe the current per-owner
multiplexer/channel registry, same-owner replacement behavior, and actual fanout
owner, without retaining the obsolete singleton claim.
