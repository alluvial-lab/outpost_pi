---
id: feature-outpost-pi-distribution-ownership
kind: feature
stage: drafting
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
