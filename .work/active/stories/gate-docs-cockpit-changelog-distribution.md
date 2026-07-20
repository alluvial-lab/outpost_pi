---
id: gate-docs-cockpit-changelog-distribution
kind: story
stage: implementing
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.2.0
gate_origin: docs
created: 2026-07-20
updated: 2026-07-20
---

# Cockpit changelog retains retired product and manifest-release guidance

## Drift category
changelog-gap

## Location
- Doc: `cockpit/CHANGELOG.md:1-5`
- Contradicting source: `docs/DECISIONS.md:120-123`

## Current doc text
> Changelog — Remote Pi Cockpit ... The `notes` field in `latest.json` (VPS) derives from this file.

## Contradiction
Current distribution is Outpost-Pi via product-prefixed GitHub Release assets; `rp-s3` is dormant and no manifest publication gate is active. The changelog header and its current release-flow instruction describe retired infrastructure.

## Required edit
Rename the current changelog surface to Outpost-Pi Cockpit and replace the retired `latest.json`/VPS assertion with the active release-notes flow. Retain historical release entries only as history, not as current operating guidance.

## Audit
Documentation drift audit ran inline because nested scanner dispatch was prohibited; isolation was reduced.
