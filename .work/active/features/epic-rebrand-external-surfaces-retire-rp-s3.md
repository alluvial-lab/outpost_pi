---
id: epic-rebrand-external-surfaces-retire-rp-s3
kind: feature
stage: drafting
tags: [rebrand, app, cockpit, rp-s3]
parent: epic-rebrand-external-surfaces
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
---

# Retire rp-s3 download server

## Brief

rp-s3 is a download/update server that served auto-update manifests
(`latest.json`) for the cockpit (desktop app) and the phone app, hosted at
`rp-s3.jacobmoura.work` on Jacob Moura's VPS (`rp-s3/docker-compose.yml`
mounts `/Users/flutterando/...` host paths). The operator has not run the
cockpit and is not exercising the phone-app update path; the host is
third-party infrastructure being retired.

This feature stops product code from pointing at the dead host. The
`UpdateCheckerImpl` auto-update code is NOT deleted (it's a working feature
that can return when distribution stands up) — its manifest URL stops
pointing at `rp-s3.jacobmoura.work`. The checker already silently returns
`null` on any network failure, so a non-resolving host is equivalent to "no
update available."

## Epic context
- Parent epic: `epic-rebrand-external-surfaces`
- Position in epic: independent mechanical feature; runs in parallel with F1
  (no-default relay) and F2 (hostname migration). Owns the
  `rp-s3.jacobmoura.work` hostname only.

## Foundation references
- `cockpit/lib/app/cockpit/data/update/update_checker_impl.dart` —
  `defaultManifestUrl = 'https://rp-s3.jacobmoura.work/downloads/cockpit/latest.json'`
- `app/lib/data/update/update_checker_impl.dart` —
  `defaultManifestUrl = 'https://rp-s3.jacobmoura.work/downloads/app/latest.json'`
- `rp-s3/docker-compose.yml` — `image: jacobmoura7/rp-s3:latest` (missed in
  commit `4697fc2`) + `rp-s3.jacobmoura.work` URL comment + `/Users/flutterando/...` host paths
- `rp-s3/README.md`, `rp-s3/build-docker.sh` — update docs to "not currently deployed"
- `cockpit/packaging/README.md` — appcast URLs
  (`rp-s3.jacobmoura.work/.../appcast-{macos,windows}.xml`)
- `site/src/lib/cockpit-release.ts`, `site/src/lib/app-release.ts` — release
  asset URLs that may point at rp-s3 or `outpost-pi.jacobmoura.work`
  (coordinate with F2 on the `outpost-pi` ones)

## Design decisions (inherited from epic)
- **rp-s3 retires from the product for now.** Auto-update `UpdateCheckerImpl`
  code stays; manifest URL becomes a non-resolving sentinel (or removed) so
  the checker silently no-ops. The feature can return when the operator
  stands up distribution.
- **rp-s3 subproject stays as dormant code** (it's a working download
  server); docs reflect "not currently deployed."

## What this feature does NOT cover
- `outpost-pi.jacobmoura.work` references in release-asset URLs — those
  migrate in F2 (hostname migration).
- The `relay-rp1` hostname — that retires in F1.

<!-- The design pass (`/agile-workflow:feature-design`) fills in the exact
manifest-URL strategy (sentinel vs removed) and the rp-s3 subproject
disposition (dormant docs update). -->
