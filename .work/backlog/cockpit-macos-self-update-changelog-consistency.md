---
id: cockpit-macos-self-update-changelog-consistency
created: 2026-07-15
updated: 2026-07-15
tags: [cockpit, docs, release]
---

# Align the Cockpit changelog with disabled macOS runtime self-update

The Unreleased entry in `cockpit/CHANGELOG.md` says Cockpit now updates itself on macOS, including background download and restart-to-install behavior. The active release/runtime contract says otherwise: `.github/workflows/cockpit-release.yml` and `cockpit/packaging/README.md` state self-update remains disabled until feeds are deployed, and `cockpit/lib/app/cockpit/cockpit_module.dart` wires `NoopSelfUpdater` on every platform because no feed URL is configured.

This is release-facing copy: the release workflow derives `latest.json` notes from the first changelog section. Rewrite the entry to distinguish generated/uploaded macOS appcast artifacts from inactive runtime self-update, while preserving the accurate Windows-disabled statement and historical release records.

**Risk rationale:** valid but non-blocking for distribution ownership. It overpromises update behavior but does not weaken signing, artifact integrity, or fail-closed release behavior, so it is parked unbound rather than holding the feature open.
