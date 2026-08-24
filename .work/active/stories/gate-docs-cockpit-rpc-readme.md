---
id: gate-docs-cockpit-rpc-readme
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

# Cockpit README presents the compatibility RPC as the active transport

## Drift category
readme-staleness

## Location
- Doc: `cockpit/README.md:10-14`
- Contradicting source: `docs/ARCHITECTURE.md:201-210`

## Current doc text
> It talks to the extension over the Pi control RPC channel (`\\x00outpost-pi-ctrl:` control frames + the generated `outpost_pi_control` schema)

## Contradiction
The structured `outpost_pi_control` custom-event path is the active Cockpit
transport. The NUL-prefixed string form is retained only as an extension-side
compatibility decoder; Cockpit does not emit it.

## Required edit
Describe Cockpit as emitting structured `outpost_pi_control` RPC envelopes and
identify the NUL-prefix form only as extension compatibility, not as a paired
active transport.
