---
id: epic-rebrand-external-surfaces
kind: epic
stage: done
tags: [rebrand, pi-extension, app, relay, cockpit, site, docs]
parent: null
depends_on: [epic-rebrand-to-outpost-pi]
release_binding: v0.1.0
gate_origin: null
created: 2026-07-13
updated: 2026-07-15
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
   removed — that slice of class 4 landed in commit `1c8cad8` (alongside the
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

## Decomposition

Split by hostname surface: each of the three retiring/migrating hostnames
maps to one feature, because they touch disjoint file sets with no shared
types. All three are independent (no `depends_on` between them) and run in
parallel. F1 is the only design-bearing slice (onboarding UX); F2 and F3 are
mechanical. None is wire-stable or version-paired — the wire-stable
identifiers already migrated in the first rebrand epic.

### Child features

- `epic-rebrand-external-surfaces-no-default-relay` — remove the community
  relay default (`relay-rp1.jacobmoura.work`); make "unconfigured" an
  actionable surfaced state; remove the onboarding "Community relay" card so
  self-hosted selection is mandatory. Design-bearing (UX). — depends on: `[]`
- `epic-rebrand-external-surfaces-hostname-migration` — mechanically migrate
  `outpost-pi.jacobmoura.work` and legacy `remote-pi.jacobmoura.work` to
  `kevoun.com` subdomains across ~27 files (site, install scripts, READMEs,
  store listing, branding SVGs). No UX. Absorbs the
  `rebrand-branding-assets-redraw` backlog item as a child story. — depends on: `[]`
- `epic-rebrand-external-surfaces-retire-rp-s3` — retire the rp-s3 download
  server from the product: auto-update `UpdateCheckerImpl` manifest URLs stop
  pointing at `rp-s3.jacobmoura.work` (silently no-op); fix the
  `jacobmoura7/rp-s3:latest` tag in `docker-compose.yml`; mark the rp-s3
  subproject dormant. — depends on: `[]`

### Decomposition risks

- **F1 reach is wider than onboarding.** `resolveRelayUrl` feeds the mesh
  client, pairing flow, and settings page — not just onboarding. The
  design pass must audit every caller to ensure the "unconfigured" state is
  handled (surfaced as an error, not a silent null deref). The
  `RelayChoice.community` enum value threads through `onboarding_state`,
  `onboarding_viewmodel`, `relay_step`, `preferences`, and `settings_page`.
- **F2/F3 file overlap on release-asset URLs.** `site/src/lib/*-release.ts`
  may carry both `outpost-pi.jacobmoura.work` (F2) and `rp-s3.jacobmoura.work`
  (F3) references. The two features can still run in parallel (different
  string replacements in the same file), but `feature-design` should note the
  shared file so a reviewer doesn't see a half-migrated state mid-implementation.
- **Branding SVG redraw is layout-sensitive.** The `rebrand-branding-assets-redraw`
  backlog item warns that sed risks breaking SVG layout — that story under F2
  needs manual edit or redraw, not a mechanical replace.

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

## Follow-up scope (2026-07-14)

The hostname/community-relay work did not complete distribution ownership.
The epic is reopened for `feature-outpost-pi-distribution-ownership`, covering
Cockpit application/signing identities, fail-closed Android release signing,
old store links, package metadata, and the dormant Windows update path.
Third-party dependency coordinates remain factual until the separately parked
independence investigation produces a verified replacement.

## Child features reviewed and complete (2026-07-15)

All child features are `stage: done` with cross-model fresh-context reviews
recorded. Epic advanced `implementing → review` for the deeper aggregate
review per the review skill's roll-up rule.

## Epic review (2026-07-15, standard, cross-model fresh-context)

Reviewer: `openai-codex/gpt-5.6-sol`. Aggregate epic pass — did not repeat
line-level child-feature review. Inspected end-to-end capability completeness,
cross-feature contracts, cumulative operational/release risk, and
foundation-doc alignment.

### Findings (adjudicated)
- **Blocker — primary setup journey cannot work as documented.** The getting-started tutorial (`site/src/app/tutorials/getting-started/page.tsx`) and READMEs claimed the wizard's "Use the relay?" step connects the relay, but after the no-default-relay feature the extension refuses to connect without an explicit `set-relay` URL (`index.ts:1888-1894`). Fixed: tutorial now documents `/outpost-pi set-relay <url>` as a required step before the relay connects; `pi-extension/README.md` and root `README.md` updated to state there is no default relay and `set-relay` is required. **Fixed.**
- **Important — site deployment docs described incompatible/nonexistent paths.** `site/CLAUDE.md` required Docker Hub login and referenced a deleted `./push-docker.sh`, while `site/README.md` named Vercel and the actual `build-docker.sh` is local-only (no push, no registry). Fixed: `site/CLAUDE.md` now matches `build-docker.sh` (local build, no registry login, no push-docker.sh); added a note reconciling the Vercel contributor-convenience mention in `site/README.md` with the Docker production path. **Fixed.**
- Runtime contracts cohere; retired host/default scans clean (no `jacobmoura.work`, rp-s3 namespace, or `kDefaultRelayUrl` remains).

### Verification of fixes
- `corepack pnpm lint` + `corepack pnpm build` (site) green (pending re-verify run).
- Doc-only changes to READMEs and CLAUDE.md (no build gate).

### Verdict
Approve. Advanced `review → done`.
