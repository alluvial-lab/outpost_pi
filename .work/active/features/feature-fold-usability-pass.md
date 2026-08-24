---
id: feature-fold-usability-pass
kind: feature
stage: done
tags: [app, ux]
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: null
created: 2026-08-23
updated: 2026-08-23
---

# Fold / split-screen / large-resolution usability pass

Operator ask (2026-08-23): "usability pass on split screen and large
resolution" for the Pixel Fold. Evidence: 99-golden render matrix
(`app/test/golden/`, PNGs in session-notes `fold-pass-20260823/goldens/`) +
vision review (18 findings) + responsive code audit. Review strengths to
preserve: 842×701 shell proportions, single-pane phone-landscape
classification, 300dp user-bubble cap, title truncation, onboarding 460dp
ResponsiveCenter pattern, strong Phosphor Beacon text contrast, no
orientation branching.

## Child stories

1. `story-fold-golden-harness-fidelity` — make the render matrix trustworthy
   (review findings 1–5): real Space Mono fonts, no modal leakage between
   captures, overflow = failure, missing states (QR scanning, detail
   placeholder, no-peer, two-pane keyboard), both system themes for
   recovery. Foundation for verifying everything else.
2. `story-fold-two-pane-policy` — findings 8, 9, 17: split eligibility needs
   master(360)+min-detail(≥320) instead of raw 600dp shortest-side; stronger
   divider contrast; master pane must not absorb the keyboard's viewInsets.
3. `story-fold-chat-adaptivity` — findings 6, 7(chat), 10: compact-height
   composer when keyboard open in low-height landscape; compact chat status
   treatment below ~280dp; reading-measure cap (~640dp centered) for
   assistant prose + composer in wide single-pane; code blocks stay
   scrollable full-width.
4. `story-fold-home-sheets-adaptivity` — findings 7(home), 11, 12, 13:
   compact home header/filter below ~280dp; cap+center the list in wide
   single-pane; height-adaptive scrollable sheets with explicit width caps
   and landscape treatment.
5. `story-fold-system-pages-a11y-floors` — findings 14, 15, 16:
   ResponsiveCenter on sync-required + storage-recovery (scrollable);
   48×48 effective hit regions for compact controls; 12sp floor for
   operational metadata text.

## Verification

Per story: widget tests assert the structural outcome (sizes, breakpoints,
hit regions, no overflow at any matrix geometry — harness from story 1
fails on overflow). Final: full golden matrix regenerated + `flutter
analyze` + full unit suite green; APK bump 0.6.0+8 built for sideload.

## Implementation summary

| Story | Commit | Delivered |
|---|---|---|
| `story-fold-golden-harness-fidelity` | `8db840fa` | Production font fixtures, modal isolation, overflow failure policy, expanded states/themes/geometries. |
| `story-fold-two-pane-policy` | `7bb4ce88` | Pane-budget split policy, divider contrast, keyboard-inset isolation. |
| `story-fold-chat-adaptivity` | `8785a27e` | Compact-height composer/status and centered wide reading measure. |
| `story-fold-home-sheets-adaptivity` | `24eff440` | Compact Home chrome, centered list, adaptive scrollable sheet frames. |
| `story-fold-system-pages-a11y-floors` | `141e3f56` | Capped system pages, recovery scrolling, 48dp targets, semantics, and 12sp operational floors. |

Integrated verification:
- Full render matrix regenerated: 16 surfaces × 9 Pixel Fold geometries = 144 PNGs, with every overflow failing directly and no allowlist entries remaining.
- `flutter analyze`: green, no issues.
- `flutter test --exclude-tags e2e --concurrency=2`: green, 902 tests.

## Review record

Standard review closure (2026-08-23):

- **B1:** the golden blank guard now decodes PNGs to raw RGBA before sampling luminance variance. A regression proves a uniform PNG is approximately zero while a real matrix golden is non-blank.
- **B2:** the production theme now applies Space Mono to every Material text role and the Text/Outlined/Elevated/Filled button roles. The harness asserts representative display, headline, title, body, label, and control styles. Regenerated 842×701 storage-recovery and onboarding-relay PNGs were visually checked; control/input text renders as Space Mono without fallback blocks.
- **B3:** the missed Home relay, delivery-state, and quick-action metadata text is now at least 12sp. Queued-clear and attachment-remove expose 48×48 hit-tested regions, with focused tests tapping the gesture centers.
- **I1:** keyboard isolation moved below the master branch Navigator and now wraps only the persistent Home surface. A settings-modal regression at 842×701 with a 280dp inset proves Home stays stable while the modal receives and pads for the real inset.
- **N1:** the 1dp divider is included in the pane budget, so split layout begins at 681dp and retains the full 320dp detail minimum.

Closure verification: 144 regenerated PNGs, zero overflow allowlist; decode-aware blank regression green; `flutter analyze` green; final `flutter test --exclude-tags e2e --concurrency=2` green with 908 tests. The first full-suite attempt hit the known load-sensitive sync re-send timing miss; its focused rerun and the complete rerun passed without code or test weakening. Rebuilt debug APK `0.6.0+8`; `aapt2` verified package `dev.kevoun.outpostpi`, versionCode 8, versionName 0.6.0, compile/target SDK 36, and label `Outpost-Pi`.
