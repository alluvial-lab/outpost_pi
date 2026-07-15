---
id: cockpit-winsparkle-marketing-version-comparison
kind: story
stage: review
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

## Implementation notes

- Changed `.github/workflows/cockpit-release.yml`: the Windows appcast now emits `${BUILD}` in `<sparkle:version>`, matching macOS and making WinSparkle compare the required monotonic pubspec `+n` build number rather than the marketing version.
- The appcast-generation comments document that inherited Remote Pi 1.5.1 Windows installations require one manual installation when an operator first enables the feed; later updates compare `+n`.
- Verification: PyYAML parsed the workflow successfully and `git diff --check` passed. The Windows appcast block was then read back to confirm it emits `${BUILD}`.
- Discrepancies: none. Parked issues: none.
