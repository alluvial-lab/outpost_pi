---
id: gate-docs-cockpit-v020-changelog-gap
kind: story
stage: done
tags: [cockpit, documentation]
parent: null
depends_on: []
release_binding: cockpit-v0.2.0
gate_origin: docs
created: 2026-07-20
updated: 2026-07-20
---

# Add the cockpit-v0.2.0 changelog entry

## Severity
High

## Drift category
changelog-gap

## Location
- Doc: `CHANGELOG.md:7`

## Current doc text
> The changelog begins with `extension-0.2.0`; it has no `cockpit-v0.2.0` section.

## Contradiction
All four items bound to `cockpit-v0.2.0` are done, but the release's public changelog has no entry for its async action ownership, typed RPC boundary, settings/control coverage, or formatter-reload observability changes. This makes the release record incomplete.

## Required edit
Add a current-state `cockpit-v0.2.0` section to `CHANGELOG.md` that accurately summarizes the four bound items, before the existing `extension-0.2.0` section. Do not add historical/progress prose.

## Audit provenance
The documentation drift scan ran inline at operator instruction, rather than in the gate's isolated scanner agent. This is reduced isolation.
