---
id: release-v0.8.1
kind: release
stage: released
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


## Shipped

- **Date**: 2026-08-26
- **Mapping**: tag-based; rc flow: rc.1 draft FAILED UAT (fullscreen over nav), deleted; rc.2 draft FAILED (ghost nav overlay), deleted; rc.3 PASSED → published as v0.8.1-rc.3, then promoted stable.
- **Items**: 1 (story-fix-app-fold-vertical-screen + 2 rc corrections riding the same story)
- **UAT**: operator-verified rc.3 (fold/nav/keyboard trio); post-pass capture 84e635f7 clean — oracles green, zero swallow/blank, zero supersede.
- **Artifacts**: outpost-0.8.1-19.apk (fat) + outpost-0.8.1-19-arm64.apk (slim) on both the rc and stable releases.

## Shipped items

| id | title | kind | archived_atop | git ref |
|----|-------|------|---------------|---------|
| story-fix-app-fold-vertical-screen | Folded viewport restored after IME/pane collapse (Pixel Fold) | story | — | 344b539d |
