---
id: feature-ci-verification-matrix
kind: feature
stage: done
tags: [workflow, security]
parent: null
depends_on: []
release_binding: v0.3.0
gate_origin: null
created: 2026-06-28
updated: 2026-07-24
---

# CI verification matrix + dependency-audit automation

## Brief

The only workflow running on push/PR today is `e2e-pairing.yml`. There is no
routine lint/typecheck/test matrix across the five subprojects and no
dependency-audit automation — both the repo-eval and the 2026-07 advisor
review flagged this as the weakest dimension (CI/CD 4/10). The 0.2.0 release
history shows the cost: test regressions and doc drift surfaced during the
release gates instead of per-push.

Add a push/PR verification matrix covering the documented per-subproject
checks (AGENTS.md "Common commands"):

- `pi-extension/`: `corepack pnpm typecheck`, `corepack pnpm test`
- `app/`: `flutter analyze`, `flutter test`
- `relay/`: `cargo fmt --check`, `cargo clippy -- -D warnings`, `cargo test`
- `cockpit/`: `flutter analyze`, `flutter test`
- `site/`: `pnpm lint`, `pnpm build`

Plus dependency-audit automation: Dependabot (or Renovate) config covering
pnpm/cargo/pub ecosystems, and an audit job (`pnpm audit`, `cargo audit` or
`cargo-deny`) with a documented severity threshold. Dependabot alerts already
fire on the repo (see commit `7d5b30d`) but nothing gates on them.

## Simplification opportunity

Path-filtered job triggering (only run a subproject's lane when its files
change) keeps the matrix cheap; a shared composite action for Flutter setup
avoids duplicating toolchain pinning across app/cockpit lanes. The existing
`e2e-pairing.yml` setup steps (Flutter install, pnpm setup) are the starting
point to factor out.

## Origin

Advisor review 2026-07-23, recommendation #1. Broadens parked backlog item
`workflow-ci-dependency-audit-gates` (repo-eval + security review finding).

## Design decisions

- **One new workflow, not a matrix-over-subprojects monolith**: `ci.yml`
  with one job per lane + `dorny/paths-filter` change detection — lanes are
  heterogeneous (three toolchains), per-job `if:` gating keeps skipped lanes
  free instead of burning a matrix leg. Rust is the exception: relay and
  rp-s3 share one lane as a 2-entry matrix (identical commands).
- **Tag-pinned actions, consistent with existing workflows** (repo uses
  `actions/checkout@v4` etc., not SHA pins) — introducing a second pinning
  style here would be drift, not improvement.
- **Audit is scheduled + lockfile-triggered, not per-push blocking**:
  dependency CVEs don't respect push cadence, and a transitive advisory
  shouldn't block unrelated work. Weekly cron + pushes that touch lockfiles.
  Fail threshold: high/critical.
- **Dependabot over Renovate**: alerts already fire on this repo (commit
  `7d5b30d` fixed transitive advisories), GitHub-native, zero extra
  infrastructure. Renovate's power isn't needed for a single-operator repo.
- **Flutter version stays per-workflow `env`** (`3.41.7`): centralizing via
  composite action would couple release workflows to ci internals. Drift
  risk accepted and noted; a version bump is a deliberate 4-file edit.
- **No APK/desktop packaging in CI**: release workflows own artifact builds;
  CI verifies source (analyze/test/typecheck) — keeps lane minutes low and
  avoids the memory tuning the VM builds need.
- **Branch protection / required checks**: a repo setting, not a workflow
  file — flagged to the operator as a follow-up, not designed here.

## Architectural choice

**Two files**: `.github/workflows/ci.yml` (verification lanes, push/PR) and
`.github/dependabot.yml` (update automation) + a `deps-audit` job inside
`ci.yml` triggered by schedule + lockfile paths. Rejected alternatives:

- **Extend `e2e-pairing.yml` with the lanes**: wrong cohesion — the e2e
  suite is a 30-min Docker/Toxiproxy job; coupling fast lanes to it slows
  the per-push signal and entangles two failure domains.
- **Reusable workflows (`workflow_call`) per subproject**: indirection a
  5-lane repo doesn't need yet; revisit if lanes grow per-OS legs.

## Implementation Units

### Unit 1: `.github/workflows/ci.yml` — verification lanes
**Story**: `feature-ci-verification-matrix-ci-lanes`

Skeleton:

```yaml
name: ci
on: [push, pull_request]
permissions:
  contents: read
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
env:
  FLUTTER_VERSION: "3.41.7"

jobs:
  changes:                       # dorny/paths-filter@v3 → per-lane outputs
    runs-on: ubuntu-24.04
    outputs: { protocol, pi-extension, rust, app, cockpit, site, lockfiles }

  protocol:    needs: changes · if: protocol || pi-extension
    # pnpm/action-setup@v4 (10) + setup-node@v4 (24, cache: pnpm)
    # working-directory: protocol → pnpm install --frozen-lockfile + check scripts

  pi-extension: needs: changes · if: pi-extension || protocol
    # pnpm install --frozen-lockfile → pnpm typecheck → pnpm test

  rust:        needs: changes · if: rust
    strategy: { matrix: { crate: [relay, rp-s3] } }
    # dtolnay/rust-toolchain@stable + Swatinem/rust-cache@v2
    # working-directory: ${{ matrix.crate }}
    # cargo fmt --check → cargo clippy -- -D warnings → cargo test

  app:         needs: changes · if: app
    # subosito/flutter-action@v2 (version from env, channel stable, cache)
    # flutter pub get → flutter analyze → flutter test
    # + nested package: app/packages/outpost_pi_identity (pub get → flutter test)

  cockpit:     needs: changes · if: cockpit
    # flutter pub get → flutter analyze → flutter test (headless; no GTK needed)

  site:        needs: changes · if: site
    # pnpm install --frozen-lockfile → pnpm lint → pnpm build

  deps-audit:  needs: changes · if: lockfiles  (plus `on: schedule` weekly)
    # pnpm audit --audit-level=high (pi-extension, site, protocol)
    # cargo audit (relay, rp-s3) via rustsec/audit-check or cargo-audit install
```

**Implementation Notes**:
- Setup steps copy the proven patterns from `e2e-pairing.yml` (pnpm 10,
  node 24, flutter-action with `PUB_CACHE` under the workspace).
- `paths-filter` watches each subproject root plus shared inputs:
  `protocol/**` triggers pi-extension + app lanes (generated DTO consumers),
  `tools/protocol-codegen/**` triggers the protocol lane.
- `deps-audit` also runs on `schedule: cron "17 4 * * 1"` and
  `workflow_dispatch`; on schedule it runs unconditionally (no path gate).

**Acceptance Criteria**:
- [ ] All six lanes green on a full-tree push
- [ ] A docs-only push runs zero lanes (path filter verified)
- [ ] A `protocol/`-only push runs protocol, pi-extension, app lanes
- [ ] e2e-pairing.yml unaffected (still runs on every push)

### Unit 2: `.github/dependabot.yml` + audit coverage
**Story**: `feature-ci-verification-matrix-dependabot-audit`

```yaml
version: 2
updates:
  - package-ecosystem: github-actions  # directory: "/", weekly
  - package-ecosystem: npm             # /pi-extension, /site, /protocol,
                                       # /e2e, /tools/protocol-codegen — weekly
  - package-ecosystem: cargo           # /relay, /rp-s3 — weekly
  - package-ecosystem: pub             # /app, /cockpit,
                                       # /app/packages/outpost_pi_identity — weekly
```

**Implementation Notes**:
- `open-pull-requests-limit: 5` per ecosystem; default commit-message
  prefix so PRs match conventional style (`deps(site): …` precedent exists).
- One npm entry per manifest directory (Dependabot requires per-directory
  entries for non-workspace repos; `protocol/` is a pnpm workspace root —
  verify whether one entry covers its members or needs per-package entries).

**Acceptance Criteria**:
- [ ] `dependabot.yml` validates (GitHub accepts it on merge; no config
  errors in the Dependency graph tab)
- [ ] Audit job fails on a deliberately introduced high-severity advisory
  (verified once via a throwaway branch, then reverted)

## Implementation Order

1. `feature-ci-verification-matrix-ci-lanes` (Unit 1) — the safety net
2. `feature-ci-verification-matrix-dependabot-audit` (Unit 2) — independent;
   can land in parallel or immediately after

## Simplification

- Setup steps deliberately copy `e2e-pairing.yml`'s proven patterns rather
  than introducing a composite action — consistency beats deduplication at
  this size. If a third Flutter-needing workflow appears, extract
  `.github/actions/setup-flutter` then (parked as a note, not a story).
- rp-s3 folds into the rust matrix instead of a fourth rust lane.
- The `app/packages/outpost_pi_identity` nested package joins the app lane
  rather than its own — its 2 test files cost seconds once Flutter is set up.

## Testing

CI configuration is verified by execution, not unit tests:
- **Lane greenness** on the landing push is the acceptance evidence.
- **Path-filter behavior** verified by the docs-only and protocol-only push
  cases above.
- **Audit threshold** verified once with a throwaway branch.
- Optional (not required): an `actionlint` pre-job if workflow syntax
  errors ever bite; skipped now for economy.

## Risks

- **Flutter cache misses** making app/cockpit lanes slow (first runs
  ~5-8 min): accepted; `flutter-action` cache is keyed and warms quickly.
- **`dorny/paths-filter` is the one new third-party action**: widely used,
  tag-pinned like the rest; the alternative (per-workflow `paths:` triggers
  across 6 workflow files) fragments the pipeline and loses the single
  required-check story.
- **pub Dependabot support is newer** than npm/cargo: if the pub entries
  error, drop them and rely on `dart pub outdated` in the weekly audit —
  recorded as the fallback, not a blocker.

## Implementation notes

- Execution capability: inline host session — two YAML files plus one config,
  cohesive single-owner delivery; no delegation value.
- Review weight: standard (default; no caller override, no project convention).
- Files changed: `.github/workflows/ci.yml` (new), `.github/workflows/deps-audit.yml`
  (new), `.github/dependabot.yml` (new).
- Tests added: none — CI configuration is verified by execution (see design);
  YAML parsed + paths-filter block validated programmatically, referenced
  package scripts confirmed to exist, `protocol` lane command (`check`)
  dry-run green locally (fixtures + 5 codegen tests pass).
- Simplification: deps-audit as its own workflow also keeps `ci.yml`'s
  path-gated lanes free of schedule/workflow_dispatch event semantics.
- Discrepancies from design:
  - `deps-audit` moved from a job inside `ci.yml` to its own workflow file —
    `dorny/paths-filter` change detection has no well-defined base on
    schedule/workflow_dispatch events; a separate file avoids event-semantics
    hacks. It triggers on weekly cron, manual dispatch, and pushes touching
    any lockfile.
  - No npm Dependabot entries for `/e2e` or `/tools/protocol-codegen` —
    neither has a `package.json` (e2e typecheck rides on pi-extension deps;
    codegen is exercised via protocol's `check:tests`).
  - Pub audit step dropped — `dart pub outdated` is informational only;
    pub update automation is covered by the three pub Dependabot entries
    (fallback note retained if the pub ecosystem errors).
- Live verification pending: lane greenness and path-filter behavior verify
  on first pushes to GitHub (cannot execute Actions locally); landing this
  commit touches `.github/workflows/ci.yml`, which every filter watches, so
  the push itself runs all six lanes as the first live check.
- Adjacent issues parked: none.

## Review record

- Effective weight: standard (one independent cross-model pass,
  openai-codex/gpt-5.6-sol, fresh context). Verdict: request changes.
- **Blocker (confirmed, fixed)**: `rustsec/audit-check@v2` has no `path`
  input — both cargo-audit matrix legs would have audited the repo root and
  failed. Fixed by switching to `taiki-e/install-action@cargo-audit` +
  `cargo audit` per crate directory.
- **Important (confirmed, fixed by the same change)**: the action's
  Checks/Issues API reporting requires write permissions the workflow
  deliberately doesn't grant; the CLI form fails via exit code like the
  pnpm audit lanes, no extra permissions. Note: plain `cargo audit` fails on
  any vulnerability advisory (no severity threshold flag) — stricter than
  pnpm's `--audit-level=high`; accepted, cargo advisories are curated.
- Reviewer-verified (not re-verified in detail): all 9 dependabot manifest
  directories exist; lane commands match AGENTS.md and package scripts;
  path-filter routing selects the intended lanes; actionlint clean.
- Closed per standard policy: blocker fixed + verified, no second pass.
