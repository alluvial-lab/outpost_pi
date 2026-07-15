---
id: story-epic-rebrand-external-surfaces-hostname-migration-mechanical-replacement
kind: story
stage: done
tags: [rebrand, pi-extension, app, cockpit, site, docs]
parent: epic-rebrand-external-surfaces-hostname-migration
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-15
---

# Replace public homepage and download hostnames

## Scope

Replace every owned `outpost-pi.jacobmoura.work` reference with
`outpost-pi.kevoun.com`, and update the Android update-banner fallback test to
assert that target. This is a data/copy-only migration: no routes, wire
messages, or runtime behavior change.

The `pi-extension/install.sh` script is canonical. Do not separately edit its
tracked site copy; `site/scripts/sync-install-sh.mjs` regenerates
`site/public/install.sh` during `pnpm build`.

## Files and exact edits

- `README.md`: official-site link only. Leave the `relay-rp1.jacobmoura.work`
  relay block to the no-default-relay feature.
- `pi-extension/install.sh`: its three installer/docs URLs.
- `pi-extension/README.md`: homepage, app-download, daemon-tutorial, and links
  URLs only. Leave the community-relay content to the no-default-relay feature.
- `pi-extension/package.json`: `homepage` field.
- `pi-extension/service-templates/systemd.service.template`: `Documentation=`.
- `app/lib/ui/update/viewmodels/update_banner_viewmodel.dart`: `_kFallbackUrl`.
- `app/test/ui/update/update_banner_viewmodel_test.dart`: matching fallback-url
  assertion.
- `app/store_listing.md`: support, marketing, and privacy URLs in both store
  sections (four references).
- `cockpit/lib/app/cockpit/ui/viewmodels/update_viewmodel.dart`: `_kFallbackUrl`.
- `site/CLAUDE.md` and `site/README.md`: deployment/target-domain documentation.
- `site/src/app/layout.tsx`: `metadataBase` and OpenGraph URL.
- `site/src/app/docs/page.tsx`: homepage display text (the link remains `/`).
- `site/src/components/install-tabs.tsx` and
  `site/src/components/landing/install.tsx`: curl-install constants.
- `site/src/lib/cockpit-release.ts`: six mock artifact URLs only. Preserve its
  `MANIFEST_URL` pointing to `rp-s3.jacobmoura.work`; that belongs to the
  retire-rp-s3 feature.
- `site/public/install.sh`: regenerated from `pi-extension/install.sh` by
  `pnpm build`; verify its three copied URLs changed.

Do not edit `site/src/lib/app-release.ts`: it currently contains only the
sibling feature's `rp-s3.jacobmoura.work` manifest URL. Do not edit
`CHANGELOG.md`: it has no owned homepage hostname and its existing relay entry
is historical/owned by the no-default-relay transition.

## Acceptance criteria

- [x] Every listed owned hostname becomes `outpost-pi.kevoun.com`, including
  `/download`, `/privacy`, `/install.sh`, and `/tutorials/daemon` paths.
- [x] `site/public/install.sh` exactly matches the canonical installer after
  `pnpm build`.
- [x] The app update-banner fallback unit test asserts
  `https://outpost-pi.kevoun.com/download`.
- [x] A scoped grep across `README.md`, `app`, `branding`, `cockpit`,
  `pi-extension`, and `site` finds no owned old homepage hostname (the SVG is
  handled by the dependent story); the retained `relay-rp1` and `rp-s3` hosts
  are untouched.
- [x] From `site/`, with repo-local pnpm caches, `pnpm lint` and `pnpm build`
  pass.

## Implementation notes

- Applied the operator-confirmed `outpost-pi.kevoun.com` mapping across the
  listed docs, installer, metadata, update fallbacks, store copy, cockpit
  mock artifacts, and site install snippets. The community relay and `rp-s3`
  hosts were left for their sibling stories.
- Kept `pi-extension/install.sh` canonical and regenerated
  `site/public/install.sh` through the site build; the copies compare exactly.
- `corepack pnpm typecheck` passed in `pi-extension/`, `flutter test
  test/ui/update/update_banner_viewmodel_test.dart` passed in `app/`, and
  `corepack pnpm lint && corepack pnpm build` passed in `site/`. The remaining
  legacy hostname is the branding SVG owned by the dependent redraw story.
