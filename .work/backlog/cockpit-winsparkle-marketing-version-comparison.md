---
id: cockpit-winsparkle-marketing-version-comparison
created: 2026-07-12
updated: 2026-07-12
tags: [cockpit, release, infra]
---

# WinSparkle appcast uses marketing version (not build number) for comparison

## Context

Found during Phase 3 convergence of the rebrand review. The cockpit release
workflow (`.github/workflows/cockpit-release.yml:365`) generates a Windows
appcast where WinSparkle compares the marketing version (`0.1.0`), not the
build number. macOS Sparkle correctly uses `sparkle:version` (CFBundleVersion =
build `+10`), so macOS users see the 0.1.0 update. But Windows users on
`1.5.1` see `0.1.0 < 1.5.1` and are NOT offered the update.

This is a pre-existing release-infra issue, not a regression introduced by the
rebrand — the rebrand just made it visible by resetting the version to 0.1.0.

## What's needed

The Windows appcast should set the WinSparkle equivalent of `sparkle:version`
to the build number (not the marketing version) so updates are offered
monotonically by build. Or document that Windows cockpit users must
reinstall manually for the 0.1.0 rebrand.

## Severity

Important (not blocking the rebrand code release; affects Windows cockpit
auto-update only). The macOS path works correctly with the `+10` build number.
