---
id: epic-rebrand-external-surfaces-retire-rp-s3-site-manifest-fallback
kind: story
stage: implementing
tags: [rebrand, site]
parent: epic-rebrand-external-surfaces-retire-rp-s3
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
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

- [ ] Absent manifest environment variables return the current mock without a
  network fetch.
- [ ] Explicit URLs retain current fetch, shape validation, and failure fallback.
- [ ] No rp-s3 URL remains in either module.
- [ ] Appropriate site static verification passes or its prerequisite is noted.
