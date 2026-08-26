---
id: feature-theme-token-cross-surface-contract-app-theme-properties
kind: story
stage: implementing
tags: [app, branding, testing]
parent: feature-theme-token-cross-surface-contract
depends_on: [feature-theme-token-cross-surface-contract-contract-tooling]
release_binding: null
gate_origin: null
created: 2026-08-26
updated: 2026-08-26
---

# Bind the mobile theme port to the shared dual-mode contract

## Checkpoint

Replace the app theme test's duplicated literal palette matrix with a fixture-backed mapping over the shared direct contract roles. Exercise `buildDarkTheme()` and `buildLightTheme()` as the stable public boundary, including brightness, `AppColors`/`AppTypography` extensions, Material `ColorScheme` wiring, and WCAG 2.1 contrast ratios for primary text/background, muted text/background, accent/background, and on-accent/accent in both modes.

Surface-specific derived roles remain native `AppColors` concerns; the fixture asserts only roles directly ported from `tokens.css`. Preserve the existing Space Mono/public-theme assertions and the useful strong-divider contrast property.

## Acceptance evidence

- The app test loads `../branding/theme-contract.json` and compares every direct shared role exposed by `AppColors.dark` and `AppColors.light` without re-listing CSS hex literals.
- Both public builders return the requested brightness and install the matching `AppColors` and `AppTypography` extensions.
- Material scheme roles remain semantically wired to the resolved palette.
- All four required color pairs meet or exceed WCAG AA normal-text ratio `4.5` in dark and light modes using the built theme values.
- `flutter analyze` and `flutter test --exclude-tags e2e` pass from `app/`.

## Ordering constraint

Requires the checked-in shared fixture and its freshness check. Its proven role-name mapping is then reused by the cockpit checkpoint.
