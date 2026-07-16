---
id: story-rebrand-site-docs-self-host-only-prose
kind: story
stage: done
tags: [rebrand, site, docs]
parent: epic-rebrand-external-surfaces
depends_on: []
release_binding: v0.1.0
gate_origin: review
created: 2026-07-14
updated: 2026-07-15
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

- [x] No `jacobmoura.work` or `relay-rp1` reference remains in `site/src/`.
- [x] No `jacobaraujo7` or `jacobmoura7` reference remains in `site/src/`.
- [x] Site docs present self-hosted relay as the only option (no community
  relay).
- [x] `pnpm lint` and `pnpm build` from `site/` pass.

## Implementation notes

- Files changed: `site/src/app/{cockpit,docs,privacy,terms,why}/page.tsx`, `site/src/app/layout.tsx`, `site/src/app/tutorials/mesh-remote/page.tsx`, `site/src/components/{header,footer}.tsx`, and `site/src/components/landing/{hero,sections}.tsx`.
- Relay docs now require building `outpost-pi-relay` from local `relay/` source; the public/community option, fallback URL, Docker Hub image, and stale GitHub references are removed.
- Privacy and terms pages now describe the self-host-only model rather than retaining inherited claims about a third-party-operated relay or its controller.
- Tests added: none (copy-only change).
- Verification: `corepack pnpm lint` and `corepack pnpm build` passed from `site/` with the required writable cache environment. (`pnpm` was not installed as a standalone executable, so Corepack supplied the project-pinned pnpm.)
- Discrepancies from design: none. The delegated instruction explicitly requested advancing this prose story directly from `drafting` to `review`.
- Adjacent issues parked: none.
