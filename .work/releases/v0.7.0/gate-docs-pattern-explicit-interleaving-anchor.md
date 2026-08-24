---
id: gate-docs-pattern-explicit-interleaving-anchor
kind: story
stage: done
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: docs
created: 2026-08-24
updated: 2026-08-24
---

# Async-interleaving pattern points at the wrong Pi-host harness line

## Drift category
pattern-skill-staleness

## Location
- Doc: `.agents/skills/patterns/explicit-async-interleaving-tests.md:43-47`
- Contradicting source: `pi-extension/test/support/e2e_pi_host_runtime.ts:268-285`

## Current doc text
> Deferred-turn settlement through the E2E pi-host — `pi-extension/test/support/e2e_pi_host_runtime.ts:175`.

## Contradiction
The cited line is the unrelated `reload` action in the host setup. The current
explicit defer/release barrier is `deferNextTurn`/`resolveDeferredTurn` at lines
269-287; the old anchor does not expose the barrier described by the pattern.

## Required edit
Refresh the pattern anchor and quoted harness example to the current explicit
started/release barrier.

## Implementation

Corrected `.agents/skills/patterns/explicit-async-interleaving-tests.md` to use
the current `deferNextTurn`/`resolveDeferredTurn` arm/release barrier at
`pi-extension/test/support/e2e_pi_host_runtime.ts:269-287`. The finding was
valid and corrected; no rejection was necessary.
