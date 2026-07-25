---
id: gate-docs-next-site-skill-version-bump
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

# next-site skill lists stale Next/React versions

## Drift category
repo-skill-staleness

## Location
- Doc: `.agents/skills/next-site/SKILL.md:11`
- Contradicting source: `site/package.json:13-16,24`

## Current doc text
> Versions/context: Next `16.2.6`, React `19.2.4`, React DOM `19.2.4`

## Contradiction
The drain upgraded Next and `eslint-config-next` to `16.2.11`,
React/React DOM are `19.2.6`, and `sharp` is now a direct dependency.

## Required edit
Update the version/context line to Next `16.2.11`, React/React DOM `19.2.6`,
and include the direct `sharp` dependency.

## Implementation notes
Updated `.agents/skills/next-site/SKILL.md` to match the versions and direct
`sharp` dependency declared in `site/package.json`.

## Review

Bounded inline review (orchestrator, 2026-07-24): edits match the Required
edit and verify against cited sources (TUI-only QR + seam, ci.yml tag
exclusion + run-pairing.sh + VM concurrency note in all five locations,
Next 16.2.11 / React 19.2.6 / direct sharp). Approved -> done.
