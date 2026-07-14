---
id: epic-rebrand-external-surfaces-hostname-migration
kind: feature
stage: drafting
tags: [rebrand, pi-extension, app, cockpit, site, docs]
parent: epic-rebrand-external-surfaces
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
---

# Migrate production hostnames to kevoun.com

## Brief

Mechanical replacement of the remaining `jacobmoura.work` production
hostnames across product source, migrating to `kevoun.com` subdomains. No UX
change, no wire change — these are display/config constants and doc
references. `kevoun.com` is already the org domain for schema `$id` URIs
(the wire-stable migration moved `remote-pi.dev` → `kevoun.com`); this
extends that to the runtime hostnames.

The site is not live, so these are constant updates, not DNS cuts — the
code carries the new target even if the host doesn't resolve yet.

## Epic context
- Parent epic: `epic-rebrand-external-surfaces`
- Position in epic: independent mechanical feature; runs in parallel with F1
  (no-default relay) and F3 (rp-s3 retirement). Owns the
  `outpost-pi.jacobmoura.work` and legacy `remote-pi.jacobmoura.work`
  hostnames only — `relay-rp1` retires in F1, `rp-s3` retires in F3.

## Foundation references
- Hostname map (from epic strategic decisions):
  - `outpost-pi.jacobmoura.work` (site/homepage) → `kevoun.com` or
    `outpost-pi.kevoun.com` — **operator confirmation pending** on exact
    subdomain; finalize at implementation time.
  - `remote-pi.jacobmoura.work` (legacy homepage, historical docs/branding
    SVG) → update to new homepage target or remove stale reference.
- Files (from epic grep, ~27 total references across these hosts):
  - `site/src/lib/cockpit-release.ts`, `site/src/lib/app-release.ts`,
    `site/README.md`, `site/CLAUDE.md`, `site/public/install.sh`
  - `pi-extension/install.sh`, `pi-extension/README.md`,
    `pi-extension/CLAUDE.md`, `pi-extension/package.json` (homepage field)
  - `README.md` (root)
  - `app/store_listing.md`, `app/lib/ui/update/viewmodels/update_banner_viewmodel.dart`
  - `cockpit/lib/app/cockpit/ui/viewmodels/update_viewmodel.dart`
  - `CHANGELOG.md` (historical — update or leave as migration record)

## Design decisions (inherited from epic)
- **kevoun.com is the org domain.** Subdomains TBD by operator; the code
  carries the new target as a constant.
- The operator does not yet have a public website stood up — site hostname
  migration is a no-op until DNS exists, but the constant is updated now.

## What this feature does NOT cover
- `relay-rp1.jacobmoura.work` — that retires in F1 (no-default relay).
- `rp-s3.jacobmoura.work` — that retires in F3.
- Branding SVG redraw (layout-sensitive, not a sed replace) — folded in as
  a child story of this feature during `feature-design`.

<!-- The design pass (`/agile-workflow:feature-design`) fills in the exact
hostname map, file-by-file replacement plan, and the branding-SVG story. -->
