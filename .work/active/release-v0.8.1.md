---
id: release-v0.8.1
kind: release
stage: quality-gate
tags: []
parent: null
depends_on: []
release_binding: v0.8.1
gate_origin: null
created: 2026-08-25
updated: 2026-08-25
---

# Release v0.8.1 (patch lane)

First two-lane patch cut under release_slicing. Fix lane only.

## Bound items
- story-fix-app-fold-vertical-screen (e5739b63) — folded viewport restored after IME collapse (Pixel Fold posture transition)

## Gate runs
Patch lane, single-fix delta: full gate suite waived per patch-lane policy (gates ran on v0.8.0 base; delta is one bounded fix with router-level regressions + goldens). Standard gates resume at v0.9.0.

## UAT (rc flow)
- v0.8.1-rc.1 draft prerelease: fat debug + arm64 slim artifacts, operator delta-UAT (fold transition repro) → publish on pass.
