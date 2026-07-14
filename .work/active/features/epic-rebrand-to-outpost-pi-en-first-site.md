---
id: epic-rebrand-to-outpost-pi-en-first-site
kind: feature
stage: drafting
tags: [rebrand, docs, i18n, site]
parent: epic-rebrand-to-outpost-pi-en-first
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
---

# EN-first + JSDoc gap-fill — site

## Brief

Translate Portuguese → English and adopt the JSDoc documentation framework in
`site/` (Next/React). 2 PT-bearing files: `site/src/app/icon.svg` (SVG comment
prose) and `site/src/app/tutorials/daemon/page.tsx` (a tutorial page — likely
PT body copy). The tutorial page is the design-bearing surface: its PT is
user-facing prose, not code comments, so it needs translation-review, not
mechanical sed.

Covers `site/src/` only. Gap-fill scope is the Always tier per the doc
convention: exported React component functions and hooks get JSDoc `/** */`
comments. React components don't have a single canonical doc framework; the
convention uses JSDoc on exported component functions/hooks where idiomatic.

## Epic context
- Parent epic: `epic-rebrand-to-outpost-pi-en-first`
- Position in epic: independent tiny slice. No `depends_on` — the site's
  product-identity strings already migrated in the first rebrand epic. Can
  run in parallel with every other child feature.

## Foundation references
- `.agents/skills/documentation-conventions/SKILL.md` — JSDoc-on-components
  format and the Always tier for React (exported components/hooks).
- `.agents/skills/next-site/SKILL.md` — site code reference; read before
  editing `site/`.
- Parent epic `## Grounded surface measurement` — the 2-file count.

## What this feature does NOT cover
- Product-identity string renames — owned by the mechanical-rename feature.
- Generated/vendored state (`.next/`, `node_modules/`).
- The `icon.svg` PT is SVG comment prose (`<!-- ... -->`) — translate to EN;
  no gap-fill (SVG is Skip tier).

## Verification
```bash
# from site/
pnpm lint && pnpm build
```
Plus a grep confirming zero PT (accented Latin) in `site/src/`.

<!-- The design pass (`/agile-workflow:feature-design`) will fill in the
component export audit and the tutorial-page translation-review plan. -->
