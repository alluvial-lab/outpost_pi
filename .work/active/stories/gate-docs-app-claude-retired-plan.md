---
id: gate-docs-app-claude-retired-plan
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

# App guidance points agents at the retired plan/ directory

## Drift category
repo-skill-staleness

## Location
- Doc: `app/CLAUDE.md:21-23`
- Contradicting source: `docs/DECISIONS.md:9-19`

## Current doc text
> Still-open decisions (final state management) live in `../plan/00-decisions.md`.

## Contradiction
The repository retired `plan/` to git history and established
`docs/DECISIONS.md` as the current decisions registry. The referenced path does
not exist in the checkout, so an app agent following this guidance cannot load
the stated source.

## Required edit
Replace the retired-plan pointer with the current durable decision surface and
retain only an explicit git-history recovery reference where historical context
is actually needed.
