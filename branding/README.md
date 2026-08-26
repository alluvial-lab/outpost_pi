# Branding — Outpost-Pi

Official visual identity, **v2.0 — Phosphor Beacon** (locked 2026-08-14).
Source of truth: SVG files (scalable). Derived PNGs generated on-VM via the
Pillow rasterizer (see below) — no external converter required.

## Identity story

An independent Alluvial-Lab product: **the beacon is lit** — a muted terminal
phosphor green against cool graphite, spoken in a mono-native voice with Space
Mono across product surfaces. The mark
is **Constellation III**: the operator's block cursor (phosphor) tethered to
two peer nodes (ink) — your session, your agents, one mesh. The block hub
deliberately breaks the share-icon/three-circles pattern; the asymmetric
spread keeps it a live system, not a diagram.

Sibling separation: Patchbay owns amber-phosphor/warm-panel + IBM Plex;
Outpost-Pi owns green-phosphor/cool-graphite + Space Mono across product
surfaces. No shared tokens.

## Palette

| Role | Dark (native) | Light |
|---|---|---|
| Background | `#0D1210` | `#F3F6F3` |
| Elevated surface | `#131A16` | `#F8FAF8` |
| Border | `#1E2620` | `#DFE6DF` |
| Text | `#E4EFE8` | `#182019` |
| Text muted | `#89978D` | `#57635A` |
| **Accent (the beacon)** | `#74CC9C` | `#256E47` |
| On-accent ink | `#0A2418` | `#FFFFFF` |

Status hues (tinted-chip usage), dark/light: success `#7FD99A`/`#3E7A4E`,
warning `#E6C86E`/`#8A6A1F`, error `#FF8B7D`/`#B34234`, info `#7DB8E8`/`#33689B`.
All pairings WCAG-AA verified in both modes. Full token set:
`../.mockups/design-system/tokens.css` (the contract every surface implements).

## Typography

**Console Mono — Space Mono across product surfaces** (400/700 + italic 400;
Google Fonts). The generated banner PNG uses the approved Noto Sans Mono
fallback because Space Mono is not installed on the build VM; the SVG source
and product surfaces retain the Space Mono contract.
Wordmark: `outpost_pi` — Space Mono 700, lowercase, letter-spacing ~0.01em
(the literal mesh name). Tagline voice: "your agents, in your pocket — the
beacon is lit."

## Mark geometry (viewBox 1024)

- Edges: `M 398 564 L 695 385 M 398 564 L 633 693`, stroke 34, round caps
- Hub cursor: rounded rect x314 y480 w168 h168 r25 (accent fill)
- Peers: circles (695,385) r63 and (633,693) r71 (ink fill)
- All geometry within the Android adaptive safe zone (r ≤ 313 of 512)

## Files

| File | Content | Use |
|---|---|---|
| `logo-full-dark.svg` | Full-bleed dark (#0D1210 bg) | Primary logo: README, store, social |
| `logo-full-light.svg` | Full-bleed light (#F3F6F3 bg) | Light-mode surfaces |
| `logo-foreground.svg` | Mark on transparency | Android adaptive foreground, iOS compose |
| `logo-background.svg` | Solid #0D1210 | Android adaptive background layer |
| `logo-monochrome.svg` | White silhouette | Android 13+ themed icon; single-color contexts |
| `banner.svg` | 1280×640: mark + wordmark + tagline + URL | GitHub README hero, social preview |

## PNG generation (on-VM, no external tools)

The mark is rects/circles/lines only — the Pillow rasterizer
(`python3` + Pillow, present on the VM) draws it natively at 4× and downscales
with LANCZOS. Standard exports:

| Platform | Size | Source |
|---|---|---|
| iOS App Icon | 1024×1024 (no alpha) | full-dark |
| Android adaptive fg/bg | 432×432 | foreground/background SVGs |
| Android monochrome | 432×432 | monochrome |
| Favicon | 32/16 | full-dark |
| npm/README logo | 512×512 | full-dark |
| Banner PNG | 1280×640 | banner.svg (source text uses Space Mono; the current VM-derived PNG uses the approved Noto Sans Mono fallback) |

## Updates

- **v2.0 — 2026-08-14**: full identity replacement (Phosphor Beacon world,
  Constellation III mark, Console Mono type). Driver: rebrand audit found all
  launcher icons + app color theme byte-identical to upstream remote_pi art.
  Exploration record: `.mockups/design-system/` (rounds 1–9 + finalists).
- v1.x: upstream-derived π+dot identity (documented in git history).
