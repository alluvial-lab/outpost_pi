---
id: feature-outpost-pi-distribution-ownership
kind: feature
stage: review
tags: [rebrand, release, infra, cockpit, app, site, security]
parent: epic-rebrand-external-surfaces
depends_on: [story-en-first-residual-maintained-surfaces]
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
---

# Make distribution identities and release infrastructure Outpost-Pi-owned

## Brief

Complete the external self-ownership conversion across application identifiers, signing, packaging, store links, and release automation. The product name and primary app identifiers moved to Outpost-Pi, but Cockpit still publishes under inherited `work.jacobmoura.cockpit` identities and a hard-coded Jacob Moura Developer ID; the Android release path retains pre-rebrand keystore naming and can fall back to debug signing; site links still target the incompatible pre-rebrand Play listing.

This feature owns the remaining distribution boundary so a future release cannot accidentally publish as the upstream author, use an inherited application identity, or appear successfully signed when operator-owned credentials are absent.

## Existing child findings

The scope promotes these existing backlog findings as child stories:

- `gate-security-release-build-debug-signing-fallback`;
- `rebrand-site-download-links-old-appid`;
- `cockpit-winsparkle-marketing-version-comparison`.

## Design requirements

The design pass should complete the child set around these arcs:

- replace Cockpit bundle/application IDs consistently across macOS, Linux, Windows, tests, desktop/metainfo filenames, and packaging configuration;
- replace inherited developer, company, copyright, homepage, author, and package metadata with operator-owned Outpost-Pi values where this repository is the publisher;
- remove hard-coded Jacob Moura signing identity and inherited absolute credential paths from release workflows and packaging docs;
- parameterize operator-owned signing/notarization identities and fail fast when required credentials are absent, without recording secrets in the repository;
- rename active pre-rebrand Android keystore/alias documentation and ensure distributable builds never silently use debug signing;
- remove or disable links to the old Play application ID until an owned listing exists;
- make Windows update ordering monotonic across the version reset, or explicitly remove the dormant appcast path until distribution is reactivated.

Genuine third-party source coordinates such as the current `jacobaraujo7/{gpt_markdown,kyroon_pty,xterm.dart}` dependencies are not to be rewritten blindly. Their independence path is tracked separately by `idea-cockpit-dependency-independence`.

The EN-first residual story precedes workflow edits so this feature does not race the translation pass across the same release files.

## Design decisions (2026-07-14, operator-confirmed)

- **Canonical Cockpit application/bundle ID: `dev.kevoun.outpostpi.cockpit` (Q1).** Mirrors the app's `dev.kevoun.outpostpi` pattern. Drives macOS `PRODUCT_BUNDLE_IDENTIFIER`, Linux app id / desktop / wm_class / metainfo `<id>` and `<launchable>`, Windows `app_id`, and the metainfo `developer` id (`dev.kevoun`).
- **macOS signing: parameterize from secret, fail closed (Q2).** Replace the hard-coded `Developer ID Application: Jacob Moura (U843T2P7A2)` with workflow inputs/secrets (`APPLE_SIGNING_IDENTITY`, `APPLE_TEAM_ID`). The workflow fails closed when the secret is absent, matching the Android signing posture. No operator certificate is baked into the repo.
- **Copyright/company metadata: mirror root LICENSE (Q3).** Cockpit `Runner.rc` (Windows) and `AppInfo.xcconfig` (macOS) carry the dual `Copyright (c) 2026 Jacob Moura / Copyright (c) 2026 Kevoun` line, matching the root `LICENSE`. Company name becomes Outpost-Pi/Kevoun where a single owner field is required.

## Architectural choice

Two parallel child stories by platform boundary, because macOS/Linux/Windows identity files are disjoint from the CI signing-parameterization work. The three already-done child stories (fail-closed Android signing, site links, Windows monotonic updates) are complete and stay under this feature. The remaining work is Cockpit platform identity + CI signing ownership.

## Implementation Units

### Unit 1: Cockpit platform application identifiers
**Files**: `cockpit/macos/Runner/Configs/AppInfo.xcconfig`, `cockpit/macos/Runner.xcodeproj/project.pbxproj`, `cockpit/linux/CMakeLists.txt`, `cockpit/linux/cockpit.desktop`, `cockpit/linux/work.jacobmoura.cockpit.metainfo.xml` (rename file → `dev.kevoun.outpostpi.cockpit.metainfo.xml`), `cockpit/linux/runner/my_application.cc`, `cockpit/linux/packaging/{deb,rpm}/make_config.yaml`, `cockpit/windows/packaging/exe/make_config.yaml`, `cockpit/windows/runner/Runner.rc`, `cockpit/packaging/README.md`
**Story**: `feature-outpost-pi-distribution-ownership-cockpit-identifiers`

Replace `work.jacobmoura.cockpit` → `dev.kevoun.outpostpi.cockpit` across all platform identifiers. Rename the metainfo XML file. Update `developer` id → `dev.kevoun`, developer name → Outpost-Pi (or Kevoun). Update Windows `CompanyName` and `LegalCopyright` to the dual copyright line. Update `cockpit/packaging/README.md` to reflect the owned app ID.

Preserve: `cockpit/CHANGELOG.md` historical release-identity record. Genuine `jacobaraujo7/*` dependency URLs stay (tracked by `idea-cockpit-dependency-independence`).

**Acceptance Criteria**:
- [ ] `rg 'work.jacobmoura.cockpit|jacobmoura' cockpit/` returns only dependency URLs and historical CHANGELOG.
- [ ] `rg 'Jacob Moura' cockpit/` returns only the dual-copyright line and historical CHANGELOG.
- [ ] `flutter analyze && flutter test` pass from `cockpit/`.

### Unit 2: CI signing ownership and identity plugin metadata
**Files**: `.github/workflows/cockpit-release.yml`, `cockpit/distribute_options.yaml`, `cockpit/packaging/README.md` (signing section), `app/packages/outpost_pi_identity/ios/outpost_pi_identity.podspec`, `app/android/app/build.gradle.kts` (keystore naming), `app/store_listing.md`
**Story**: `feature-outpost-pi-distribution-ownership-ci-signing`

- Remove hard-coded `Developer ID Application: Jacob Moura (U843T2P7A2)` from the workflow and `distribute_options.yaml`; read from `APPLE_SIGNING_IDENTITY` / `APPLE_TEAM_ID` secrets; fail closed when absent.
- Update `app/packages/outpost_pi_identity/ios/outpost_pi_identity.podspec` homepage (`jacob-moura/remote_pi` → `KevounC/outpost_pi`) and author (Outpost-Pi / Kevoun).
- Rename the Android keystore documentation from `remotepi-release.jks` / alias `remotepi` to `outpostpi-release.jks` / alias `outpostpi` across `app-release.yml`, `store_listing.md`, and `build.gradle.kts` comments. The fail-closed behavior is already done; this is the naming cleanup.

**Acceptance Criteria**:
- [ ] `rg 'Developer ID Application: Jacob Moura|jacob-moura/remote_pi|remotepi-release' .github/ cockpit/ app/` returns no hits (excluding historical CHANGELOG).
- [ ] YAML parses for both release workflows.

## Implementation Order
1. `feature-outpost-pi-distribution-ownership-cockpit-identifiers` (Unit 1) — no deps
2. `feature-outpost-pi-distribution-ownership-ci-signing` (Unit 2) — no deps, parallel with 1

Both touch disjoint files and can run in parallel.

## Testing
- Cockpit: `flutter analyze && flutter test` (from `cockpit/`)
- Workflows: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/cockpit-release.yml'))"`

## Risks
- **macOS bundle ID change is a one-way door**: existing Cockpit installs cannot upgrade in place (different bundle ID). This mirrors the app's `applicationId` cutover. Acceptable per the operator's self-ownership stance; document the reinstall requirement.
- **Operator Apple Developer ID not yet provisioned**: the workflow will fail closed until `APPLE_SIGNING_IDENTITY`/`APPLE_TEAM_ID` secrets exist. This is the intended posture — Cockpit binary release is blocked until the operator provisions signing, not silently published unsigned.

## Keep-list (do NOT change)
- `cockpit/CHANGELOG.md` historical release-identity record
- Genuine `jacobaraujo7/*` dependency coordinates
- `cockpit/pubspec.yaml`/`pubspec.lock` dependency URLs

