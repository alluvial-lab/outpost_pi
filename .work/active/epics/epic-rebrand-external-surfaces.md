---
id: epic-rebrand-external-surfaces
kind: epic
stage: drafting
tags: [rebrand, pi-extension, app, relay, cockpit, site, docs]
parent: null
depends_on: [epic-rebrand-to-outpost-pi]
release_binding: null
gate_origin: null
created: 2026-07-13
updated: 2026-07-14
---

# Rebrand external surfaces: retire community relay, migrate hostnames

## Brief

The first rebrand epic (`epic-rebrand-to-outpost-pi`, `stage: review`) shipped
the code-internal rename, wire/install-stable identifier migration, and
provenance — scope classes 1–3. It **explicitly deferred scope class 4
(external surfaces)** to a follow-up epic: *"GitHub repo rename, npm publish
target, homepage, branding assets, and site/marketing copy are not part of
this epic. External identity moves separately."* This is that follow-up epic.

Two changes since then collapse the scope:

1. **The GitHub repo is now `KevounC/outpost_pi`** and the fork network is
   removed — that slice of class 4 landed in commit `4697fc2` (alongside the
   posture-vocabulary cleanup). The `jacobaraujo7` GitHub user and
   `jacobmoura7` Docker Hub namespace references are gone from product
   source.
2. **The operator is not standing up a public relay.** The community relay
   (`relay-rp1.jacobmoura.work`) is Jacob Moura's infrastructure and is
   being retired from the product. Outpost-Pi becomes local-relay-only:
   every install runs its own relay from `relay/` source, or points at an
   operator-chosen self-hosted relay.

What remains is the **`jacobmoura.work` hostname migration** (4 distinct
production hostnames across ~27 files) plus the removal of the community-relay
default and the rp-s3 download server.

## Strategic decisions

- **Default relay fallback: none.** Both clients (`pi-extension/src/config.ts`,
  `app/lib/data/transport/relay_config.dart`) currently hard-fallback to
  `kDefaultRelayUrl`. After this epic, there is no default. An empty/absent
  relay URL means "not configured" — the pairing/onboarding flow must force
  explicit relay selection before any connection is attempted. Rationale: the
  product no longer ships a public relay; a silent fallback to a dead
  third-party host would produce confusing connection timeouts.
- **kevoun.com is the org domain.** Already established for schema `$id` URIs
  (the wire-stable migration moved `remote-pi.dev` → `kevoun.com` across all
  `protocol/schema/*.json`). Production hostnames migrate to `kevoun.com`
  subdomains. The operator does not yet have a public website stood up, so
  the homepage/site hostname migration is a no-op until DNS exists — recorded
  here but not blocked on infrastructure.
- **rp-s3 (download/update server) retires from the product for now.** It
  served auto-update manifests for the cockpit (desktop app, not yet run by
  the operator) and the phone app, from `rp-s3.jacobmoura.work`. The host
  paths in `rp-s3/docker-compose.yml` point at `/Users/flutterando/...`
  (Jacob Moura's VPS). The auto-update `UpdateCheckerImpl` code is not deleted,
  but its manifest URLs stop pointing at a dead third-party host. The
  auto-update feature can return when the operator stands up distribution.
- **Hostname map** (operator confirmation pending; `kevoun.com` subdomains):
  - `relay-rp1.jacobmoura.work` → **retired** (community relay removed; see
    "no default" decision above). References become empty/non-configured
    rather than re-pointed.
  - `outpost-pi.jacobmoura.work` (site/homepage) → `kevoun.com` or
    `outpost-pi.kevoun.com` — **deferred** until DNS/website exists. No live
    reference should point at the old hostname; site code carries the new
    target as a constant even if the host doesn't resolve yet.
  - `rp-s3.jacobmoura.work` → **retired** (rp-s3 fate above).
  - `remote-pi.jacobmoura.work` (legacy homepage, appears only in historical
    docs/CHANGELOG + branding SVG) → update to the new homepage target or
    remove the stale reference.

## Scope

Three workstreams, each a child feature. They are disjoint and can proceed in
parallel; none is wire-stable or version-paired (the wire-stable identifiers
already migrated in the first rebrand epic).

### Feature 1 — Remove community relay default (no-default relay)

The deepest-reaching slice: changes onboarding UX, not just constants.

- `pi-extension/src/config.ts`: `kDefaultRelayUrl` → removed (or empty). The
  `resolveRelayUrl()` precedence chain (env → config → default) must handle
  "no default" — return a `source: "unconfigured"` state that the caller
  surfaces as an actionable error ("set a relay via /outpost-pi set-relay"),
  not a silent fallback.
- `app/lib/data/transport/relay_config.dart`: same — `kDefaultRelayUrl`
  removed, `resolveRelayUrl` returns null/unconfigured when no preference.
- `app/lib/ui/onboarding/widgets/relay_step.dart`: the "Community relay"
  card (with `footer: kDefaultRelayUrl`) is removed. Onboarding forces
  self-hosted relay selection — the custom-URL card becomes the only path,
  and an empty URL is no longer accepted (today empty → "use default").
- `app/lib/ui/onboarding/viewmodels/onboarding_viewmodel.dart`: the
  "empty = default" logic in the relay validation must reject empty.
- Tests: `pi-extension/src/config.test.ts`, `app/test/data/transport/
  relay_config_test.dart`, `app/test/ui/update/...` — update assertions that
  assume a default URL; add tests for the unconfigured state.

### Feature 2 — Migrate production hostnames to kevoun.com

The mechanical hostname replacement across product source. No UX change.

- Site/homepage: `outpost-pi.jacobmoura.work` → `kevoun.com` (or
  `outpost-pi.kevoun.com`) across `site/src/lib/*-release.ts`,
  `site/README.md`, `site/CLAUDE.md`, `site/public/install.sh`,
  `pi-extension/install.sh`, `pi-extension/README.md`, `README.md`,
  `app/store_listing.md`, `cockpit/.../update_viewmodel.dart`,
  `app/lib/ui/update/viewmodels/update_banner_viewmodel.dart`. Note: the
  site is not live, so these are constant updates, not DNS cuts.
- Legacy `remote-pi.jacobmoura.work` references (CHANGELOG, branding SVGs,
  backlog) → update or remove.
- Does **not** touch `relay-rp1` or `rp-s3` (those retire, Features 1 & 3).

### Feature 3 — Retire rp-s3 download server

- `cockpit/lib/app/cockpit/data/update/update_checker_impl.dart` and
  `app/lib/data/update/update_checker_impl.dart`: `defaultManifestUrl`
  pointing at `rp-s3.jacobmoura.work/downloads/...` → the auto-update
  checker should no-op (return null) or point at a future-distribution URL
  the operator will stand up. Decision: leave the `UpdateCheckerImpl` code
  intact but set the manifest URL to a non-resolving sentinel or remove the
  default so the checker silently no-ops (it already returns null on any
  failure — a non-resolving host is equivalent to "no update available").
- `rp-s3/docker-compose.yml`: the `image: jacobmoura7/rp-s3:latest` tag (missed
  in commit `4697fc2`) plus the `rp-s3.jacobmoura.work` URL comment.
- `rp-s3/README.md`, `rp-s3/build-docker.sh`: decide whether the rp-s3
  subproject stays as dormant code or is removed. Recommend: keep as dormant
  code (it's a working download server), update its docs to reflect
  "not currently deployed."
- `cockpit/packaging/README.md`: appcast URLs (`rp-s3.jacobmoura.work/.../appcast-{macos,windows}.xml`)
  and the `work.jacobmoura.cockpit` app-id prose (the app-id itself is
  wire-stable and already migrated to `dev.kevoun.outpostpi` — check whether
  packaging docs still carry stale prose).

## Absorb the branding-asset backlog item

`.work/backlog/rebrand-branding-assets-redraw.md` ("Branding assets still say
Remote Pi") explicitly defers to "the external-surfaces follow-up epic." It
belongs here: the SVG assets (`branding/banner.svg`, `logo-*.svg`) carry
"Remote Pi" text and `remote-pi.jacobmoura.work` URLs that need a redraw (sed
risks breaking SVG layout). Fold it in as a child story under Feature 2
(hostname migration) or a standalone story if the redraw work is independent.

## Acceptance criteria

- [ ] No `jacobmoura.work` hostname remains in product source (excluding
  historical CHANGELOG entries that record the migration).
- [ ] `kDefaultRelayUrl` no longer points at `relay-rp1.jacobmoura.work`;
  both clients have no silent default and surface an actionable
  "unconfigured" state.
- [ ] The onboarding "Community relay" card is removed; self-hosted relay
  selection is mandatory.
- [ ] rp-s3 manifest URLs no longer point at `rp-s3.jacobmoura.work`;
  auto-update silently no-ops rather than fetching from a dead host.
- [ ] `rp-s3/docker-compose.yml` no longer references `jacobmoura7/rp-s3`.
- [ ] Branding SVGs carry the Outpost-Pi wordmark + the new (or no) URL.
- [ ] `pi-extension` typecheck + tests pass; `app` analyze + tests pass;
  `cockpit` analyze + tests pass (where touched).
- [ ] PROTOCOL.md updated if the "no default relay" decision changes any
  documented relay-resolution contract.

## Why an epic, not features

The three workstreams share a strategic frame (external identity migration +
community-relay retirement) and the first rebrand epic explicitly named this
as the class-4 follow-up. The onboarding-UX change in Feature 1 is
design-bearing enough to warrant a design pass, and the hostname map +
rp-s3 fate are operator-confirmed strategic decisions recorded above. Hand
to `epic-design` to decompose into child features with `depends_on` chains
(Feature 1 is the only one with UX reach; Features 2 & 3 are mechanical and
can run in parallel with 1 once the hostname map is confirmed).

## Verification

From the owning subproject roots:

```bash
# pi-extension
corepack pnpm typecheck && corepack pnpm test

# app
flutter analyze && flutter test

# cockpit (if update_checker touched)
flutter analyze && flutter test
```

Plus a repo-wide grep confirming zero `jacobmoura.work` references in
product source (excluding historical CHANGELOG prose).
