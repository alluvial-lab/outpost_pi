---
id: gate-docs-changelog-v0120
kind: story
stage: implementing
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.12.0
gate_origin: docs
created: 2026-09-07
updated: 2026-09-07
---

# Root changelog has no v0.12.0 entry for the gated bundle

## Drift category
changelog-gap

## Location
- Doc: `CHANGELOG.md:1-2`
- Contradicting source: `.work/active/release-v0.12.0.md:14-32`

## Current doc text
> `CHANGELOG.md` begins with `## v0.11.1 — 2026-08-29`; it has no `v0.12.0`
> section recording the current release bundle.

## Contradiction
The v0.12.0 bundle contains the telemetry room-meta fields and mobile rendering, the fleet update command/coordinator/settings flow, and the sync-history default change. It also rides post-v0.11.1 fixes for background re-broadcast, bare-Pi `/new` verification, connection close attribution, and relay WebSocket stream-error diagnostics. None has a v0.12.0 changelog entry, so the release's human-facing change record omits the gated work.

## Required edit
Add a current `v0.12.0` section before `v0.11.1` with concise feature, fix, and internal entries covering the two features, the 200-event sync default, and the post-v0.11.1 trunk fixes. Describe active behavior, not release-process history or superseded state.
