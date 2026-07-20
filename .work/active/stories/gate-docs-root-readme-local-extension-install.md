---
id: gate-docs-root-readme-local-extension-install
kind: story
stage: review
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.2.0
gate_origin: docs
created: 2026-07-20
updated: 2026-07-20
---

# Root README directs operators to an npm install instead of the local extension

## Drift category
readme-staleness

## Location
- Doc: `README.md:82-103`
- Contradicting source: `AGENTS.md:117,131-134`

## Current doc text
> Install the Pi extension ... `pi install npm:outpost-pi` ... Planning notes and roadmap live in `plan/`.

## Contradiction
The checked-out extension is authoritatively loaded through Pi's local-path extension setting and its generated `dist/index.js`; it is not rebuilt automatically. The retired `plan/` directory is not the current roadmap surface.

## Required edit
Replace the npm install quick-start with the supported local-path registration and build/restart instructions, and point status/roadmap readers to current durable documentation. Keep the README operator-oriented.

## Audit
Documentation drift audit ran inline because nested scanner dispatch was prohibited; isolation was reduced.

## Implementation notes
- **Execution:** Bounded inline operator-documentation repair; local Pi settings and the package entrypoint provide the supported install contract.
- **Change:** Replaced the nonexistent npm install with checkout build, local `extensions` registration, and full-restart steps; replaced the retired `plan/` roadmap pointer with durable foundation docs.
- **Verification:** Confirmed `pi-extension/package.json` loads `dist/index.js`, Pi settings accept local extension directories, and the stale npm/plan guidance is absent. No automated test applies to this prose-only correction.
- **Bounded inline review:** Pass — the quick start is operator-focused and preserves existing settings explicitly.
