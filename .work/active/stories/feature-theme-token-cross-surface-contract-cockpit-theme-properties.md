---
id: feature-theme-token-cross-surface-contract-cockpit-theme-properties
kind: story
stage: implementing
tags: [cockpit, branding, testing]
parent: feature-theme-token-cross-surface-contract
depends_on: [feature-theme-token-cross-surface-contract-app-theme-properties]
release_binding: null
gate_origin: null
created: 2026-08-26
updated: 2026-08-26
---

# Bind the cockpit theme port to the shared dual-mode contract

## Checkpoint

Replace the cockpit theme test's duplicated literal palette matrix with the same fixture-backed direct-role mapping established by the mobile checkpoint. Exercise both `buildTokens(brightness: ...)` and `buildTheme(brightness: ...)`, proving the token bundle and shadcn `ColorScheme` resolve the same dark/light palette and meet WCAG 2.1 contrast requirements.

Cockpit-only syntax, terminal, git, and file roles remain native derived roles; retain focused typography/syntax/terminal assertions where they protect a separate contract rather than repeating the shared palette.

## Acceptance evidence

- The cockpit test loads `../branding/theme-contract.json` and compares every direct shared role exposed by `AppColors.dark` and `AppColors.light` without re-listing CSS hex literals.
- `buildTokens` and `buildTheme` are invoked for both brightness modes and agree on brightness and semantic role wiring.
- Shadcn background/foreground, card, primary, primary-foreground, secondary, muted, muted-foreground, destructive, border, and ring slots map to the intended resolved roles.
- Primary text/background, muted text/background, accent/background, and on-accent/accent each meet or exceed WCAG AA normal-text ratio `4.5` in both modes.
- `flutter analyze` and `flutter test` pass from `cockpit/`.

## Ordering constraint

Apply after the app checkpoint so both Flutter suites use one established fixture role vocabulary rather than inventing parallel aliases.
