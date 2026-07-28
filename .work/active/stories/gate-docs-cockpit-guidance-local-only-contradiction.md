---
id: gate-docs-cockpit-guidance-local-only-contradiction
kind: story
stage: review
tags: [cockpit, documentation]
parent: null
depends_on: []
release_binding: null
gate_origin: docs
created: 2026-07-20
updated: 2026-07-28
---

# Reconcile Cockpit's local-only guidance with its active control overlay

## Severity
Medium

## Drift category
foundation-doc-assertion

## Location
- Doc: `cockpit/CLAUDE.md:6-9,18-20,174-176`
- Contradicting source: `cockpit/lib/app/cockpit/ui/session/agent_session.dart:509-518`

## Current doc text
> Each agent is a local `pi --mode rpc` process — “no relay, pairing, or crypto.”
>
> “Remote control (relay/mesh/crypto) is active through the RPC-control overlay.”
>
> “Add **relay, mesh, crypto, or pairing** at this stage — Cockpit is local-only.”

## Contradiction
The same current Cockpit guide says remote control is active while its opening and prohibited-work guidance still describe relay/mesh/crypto control as future local-only work. The active agent session sends relay control commands through the RPC-control overlay, so the obsolete prohibition can direct maintainers away from existing behavior.

## Required edit
Rewrite the Cockpit scope and prohibited-work statements in place to distinguish the active RPC-control overlay from still-deferred remote capabilities. Keep the established local process ownership and do not claim unsupported direct relay/pairing behavior.

## Audit provenance
The documentation drift scan ran inline at operator instruction, rather than in the gate's isolated scanner agent. This is reduced isolation.

## Implementation notes

- Rewrote `cockpit/CLAUDE.md` scope and prohibited-work guidance to document the active RPC-control overlay while preserving local Pi process ownership and deferred direct relay/mesh transport.
- No code or tests changed (documentation-only story).
- Verification: final `flutter analyze` and `flutter test` run for the completed cockpit batch.
- Parked issue: none.
