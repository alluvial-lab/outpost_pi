---
id: epic-rebrand-external-surfaces-retire-rp-s3-site-manifest-fallback
kind: story
stage: done
tags: [rebrand, site]
parent: epic-rebrand-external-surfaces-retire-rp-s3
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-15
---

# Remove rp-s3 defaults from site release loaders

Implement Unit 2 of the parent feature.

## Scope

- `site/src/lib/app-release.ts`: retain `NEXT_PUBLIC_APP_MANIFEST_URL` as an
  optional override but remove its rp-s3 default. If absent, return
  `APP_MOCK_MANIFEST` with `live: false` before `fetch`.
- `site/src/lib/cockpit-release.ts`: make the equivalent change for
  `NEXT_PUBLIC_COCKPIT_MANIFEST_URL` and `MOCK_MANIFEST`.
- Rewrite only comments that describe rp-s3/VPS defaults.
- Leave every `outpost-pi.jacobmoura.work` mock artifact URL exactly unchanged;
  it belongs to sibling feature
  `epic-rebrand-external-surfaces-hostname-migration`.

## Acceptance criteria

- [x] Absent manifest environment variables return the current mock without a
  network fetch.
- [x] Explicit URLs retain current fetch, shape validation, and failure fallback.
- [x] No rp-s3 URL remains in either module.
- [x] Appropriate site static verification passes or its prerequisite is noted.

## Implementation notes

- Removed the hard-coded rp-s3 fallback while preserving each environment
  variable as an optional manifest URL override. The loaders now return their
  existing mock immediately when the override is absent, so no network request
  is attempted; configured URLs still use the existing fetch, shape validation,
  and catch fallback path.
- Preserved all `outpost-pi.jacobmoura.work` mock artifact URLs unchanged; this
  story intentionally does not take on the sibling hostname migration.
- Verification: with the required writable pnpm/cache environment configured,
  `corepack pnpm lint` and `corepack pnpm build` both passed from `site/`.
