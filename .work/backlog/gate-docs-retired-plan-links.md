---
id: gate-docs-retired-plan-links
created: 2026-08-26
updated: 2026-08-26
tags: [documentation]
release_binding: null
gate_origin: docs
---

# Current documentation still links to retired plan files

## Drift category
repo-skill-staleness

## Location
- Doc: `cockpit/CLAUDE.md:12-13`; `PROTOCOL.md:591-594`; `docs/ARCHITECTURE.md:292-293`
- Contradicting source: `docs/DECISIONS.md:15-19`; repository tree has no `plan/` directory

## Current doc text
> `Reference plan: ../plan/37-desktop-cockpit.md`
>
> `Architectural plans: [plan/](plan/)`
>
> `per plan/00-decisions.md`

## Contradiction
The durable decision registry states that `plan/` was retired to git history. These current guidance links are broken or present the retired file as an operative source, so agents and users cannot follow the cited references from the current checkout.

## Required edit
Replace current links with the durable `docs/DECISIONS.md`, `docs/SPEC.md`, `docs/ARCHITECTURE.md`, or `PROTOCOL.md` surfaces. Where historical plan context matters, use the documented `git show <commit>:plan/...` recovery wording without presenting the retired path as a live document.
