---
id: gate-docs-pattern-asymmetric-threshold-anchor-v080
kind: story
stage: implementing
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.8.0
gate_origin: docs
created: 2026-08-25
updated: 2026-08-25
---

# Asymmetric-threshold pattern points at post-probe connection code

## Drift category
pattern-skill-staleness

## Location
- Doc: `.agents/skills/patterns/asymmetric-threshold-stabilization.md:63-76`
- Contradicting source: `app/integration_test/live_infra_smoke_test.dart:218-228`

## Current doc text
> The live runner example is at `app/integration_test/live_infra_smoke_test.dart:229-244` and requires five consecutive healthy probes.

## Contradiction
The cited range now begins at the `connectTo` call after the probe. The five-probe counter and reset behavior are at lines 218-228, so the documented anchor no longer exposes the stabilization contract.

## Required edit
Refresh the live-runner example anchor and quoted snippet to `live_infra_smoke_test.dart:218-228`.
