---
id: gate-docs-pattern-resource-policy-anchor
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

# Centralized-resource pattern cache anchor no longer shows eviction

## Drift category
pattern-skill-staleness

## Location
- Doc: `.agents/skills/patterns/centralized-resource-policy.md:77-81`
- Contradicting source: `relay/src/handlers/pi_forward.rs:165-176`

## Current doc text
> The cache enforces both freshness and a named capacity from the same policy module — `relay/src/handlers/pi_forward.rs:146-154`.

## Contradiction
The cited range now shows in-flight scan admission. The cache freshness and
capacity eviction code moved below it, so the pattern's resource-policy example
no longer points at the behavior it claims to demonstrate.

## Required edit
Refresh the pi-forward cache anchor and snippet to the current freshness,
capacity, and named-policy enforcement.
