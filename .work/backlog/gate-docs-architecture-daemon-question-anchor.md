---
id: gate-docs-architecture-daemon-question-anchor
created: 2026-08-26
updated: 2026-08-26
tags: [documentation]
release_binding: null
gate_origin: docs
---

# Architecture points daemon guidance at the wrong SPEC open-question section

## Drift category
foundation-doc-assertion

## Location
- Doc: `docs/ARCHITECTURE.md:52`
- Contradicting source: `docs/SPEC.md:169-177`

## Current doc text
> First-class long-running mode (see Open questions §3 in SPEC).

## Contradiction
The daemon decision is documented as Open questions item 2 in `docs/SPEC.md`; item 3 is the fork product direction. The cross-reference sends readers to an unrelated decision, especially confusing beside the fresh-session daemon work.

## Required edit
Change the cross-reference to Open questions §2 in `docs/SPEC.md`, or point directly to the durable daemon decision surface in `docs/DECISIONS.md`.
