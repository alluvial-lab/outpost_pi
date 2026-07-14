---
id: story-rebrand-site-docs-self-host-only-prose
kind: story
stage: drafting
tags: [rebrand, site, docs]
parent: epic-rebrand-external-surfaces
depends_on: []
release_binding: null
gate_origin: review
created: 2026-07-14
updated: 2026-07-14
---

# Rewrite site docs prose for local-relay-only + kevoun.com

## Brief

Phase 8 review finding B3. The site docs (`site/src/app/docs/page.tsx`,
`why/page.tsx`, `tutorials/mesh-remote/page.tsx`, `privacy/page.tsx`,
`terms/page.tsx`, `cockpit/page.tsx`, `components/{header,footer}.tsx`) still
advertise a "community relay" / "public relay" and carry stale
`jacobaraujo7/outpost_pi` and `jacobmoura7/outpost-pi-relay` references in
prose. The epic's decision is local-relay-only — these pages must be rewritten
to self-host-only framing, with the remaining 2 `relay-rp1.jacobmoura.work`
literal refs (docs/page.tsx:349, 451) removed as part of the "Option A —
community relay" subsection rewrite.

Also: any `jacobaraujo7/outpost_pi` or `jacobmoura7/*` GitHub/Docker references
in site prose → `KevounC/outpost_pi` / project-local.

## Scope

- `site/src/app/docs/page.tsx` — rewrite the relay-setup section: remove
  "Option A — Use the community relay" subsection; make self-hosted the only
  path. Remove `relay-rp1.jacobmoura.work` at lines 349, 451.
- `site/src/app/why/page.tsx:44` — "Run the community relay or host your own"
  → self-host-only.
- `site/src/app/tutorials/mesh-remote/page.tsx:155` — community-relay mention.
- `site/src/app/privacy/page.tsx`, `terms/page.tsx` — relay-provenance prose.
- Any `jacobaraujo7/outpost_pi` / `jacobmoura7/outpost-pi-relay` refs in site
  prose → KevounC/outpost_pi / project-local-build.

## Acceptance criteria

- [ ] No `jacobmoura.work` or `relay-rp1` reference remains in `site/src/`.
- [ ] No `jacobaraujo7` or `jacobmoura7` reference remains in `site/src/`.
- [ ] Site docs present self-hosted relay as the only option (no community
  relay).
- [ ] `pnpm lint` and `pnpm build` from `site/` pass.
