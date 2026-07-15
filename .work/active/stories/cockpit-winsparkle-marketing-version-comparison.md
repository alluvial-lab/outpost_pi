---
id: cockpit-winsparkle-marketing-version-comparison
kind: story
stage: implementing
tags: [cockpit, release, infra]
parent: feature-outpost-pi-distribution-ownership
depends_on: [story-en-first-residual-maintained-surfaces]
release_binding: null
gate_origin: null
created: 2026-07-12
updated: 2026-07-14
---

# Make Windows Cockpit update ordering monotonic

## Context

The Cockpit release workflow generates a Windows appcast where WinSparkle compares the marketing version (`0.1.0`) rather than a monotonic build number. Users on inherited `1.5.1` builds therefore do not see the rebranded `0.1.0` update even though the new artifact is later. macOS Sparkle already compares the build number correctly.

Manifest publication and self-update are currently dormant, but this invalid inherited path must not be presented as release-ready distribution infrastructure.

## Required outcome

Use the WinSparkle equivalent of a monotonic build version, or remove the dormant Windows appcast publication path until an operator-owned distribution channel is deliberately reactivated. Document any required one-time manual reinstall for the version reset.

The implementation follows the EN-first workflow translation because both edit `.github/workflows/cockpit-release.yml`.
