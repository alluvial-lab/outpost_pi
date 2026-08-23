---
id: feature-fold-usability-pass
kind: feature
stage: implementing
tags: [app, ux]
parent: null
depends_on: []
release_binding: null
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

## Review record

Filled at completion.
