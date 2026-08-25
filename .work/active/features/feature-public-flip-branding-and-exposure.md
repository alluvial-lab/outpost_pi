---
id: feature-public-flip-branding-and-exposure
kind: feature
stage: drafting
tags: [branding, security, ops, release]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-14
updated: 2026-08-14
---

# Public flip: branding holdover cleanup + private-layer exposure remediation

Forensic audit 2026-08-14 (hash-compared against upstream main; image reads
unavailable this session — provenance established via git hash-object).

## A. Look-and-feel holdovers (all CONFIRMED upstream artifacts)

1. **Launcher icons are upstream's art, byte-identical**: Android adaptive
   set + iOS AppIcon set in `app/` hash-match `jacobaraujo7/remote_pi@main`.
   Cockpit macOS/Windows icons use the same 1024 source
   (`c7614537…`). The rebrand propagated upstream art, not new art.
2. **`app/lib/ui/core/themes/app_colors.dart` is byte-identical to
   upstream's** — the mobile app's whole color theme is upstream's.
3. **The documented brand palette (black/white/#4FC3F7, branding/README.md)
   is referenced by ZERO code** — it exists only in branding/ SVGs.
4. **Site art diverged**: `site/public/logo.svg` + `site/app/icon.svg` differ
   from `branding/logo-full.svg` (stale/PT-era variants, likely pre-rebrand).
5. **`branding/screenshot-app.png`** (used on site cockpit page) predates any
   re-rebrand; retake after new look lands.
6. Fonts: vestigial commented Schyler/Trajan Pro stanzas in app+cockpit
   pubspecs (upstream leftovers). Runtime fonts via google_fonts (fine).
7. Acceptable as-is: README MIT attribution, cockpit CHANGELOG historical
   "Remote Pi" entries (history), legacy-migration identifiers in tests.

## B. Private-layer exposure if repo goes public (the hard blocker)

- **957 tracked files** of private ops across `.work/` (session notes with
  incident detail), `.research/`, `.orchestration/`, `.claude/`, `review/`,
  `REPO-EVAL.md`, root `AGENTS.md`/`CLAUDE.md` (full deploy runbook with
  LAN/tailnet IPs, VM hostname, phone setup).
- **~1,397 commits of history touching `.work/` alone** — a public flip
  exposes ALL history, so tree cleanup alone is insufficient.
- Scattered: `scripts/herdr-setup.sh` comment (LAN IP), fixture hostname
  `dev-vm` (cosmetic). Site docs page tailscale mentions are benign links.

## Status: DESIGN LOCKED 2026-08-14 — implementation pending

Identity complete (see `.mockups/design-system/` + `branding/`):
- **World**: Phosphor Beacon — dark-native #0D1210 / light #F3F6F3, accent
  #74CC9C / #256E47, full status set AA-verified both modes.
- **Mark**: Constellation III, enlarged — block-cursor hub (phosphor) + two
  peer nodes (ink). Canonical SVGs in `branding/` (v2.0; upstream-derived
  logo-full.svg + banner.png removed). Share-icon neighbor-audited.
- **Type**: Console Mono — Space Mono everywhere; wordmark `outpost_pi` 700.
- **Contract**: `.mockups/design-system/tokens.css` (dual-mode, 8pt, radii).
- **PNG pipeline**: Pillow 11 on the VM rasterizes the mark natively
  (rects/circles/lines + supersample + LANCZOS) — no external SVG converter
  needed; banner wordmark text wants Space Mono present at export time.

Remaining child stories: icon regeneration sweep (app/cockpit/site PNGs,
 hash-verify ≠ upstream), app+cockpit theme replacement (app_colors.dart is
 byte-identical to upstream), site logo sync, screenshot retake. Typography
 implementation = Space Mono via google_fonts in app/cockpit (already a dep),
 tokens.css ported to Tailwind/CSS vars on site.

## Licensing verdict (adversarial review, 2026-08-15 — gpt-5.6-sol cross-model)

**Source repo: CLEAR to flip public** after in-line fixes (all landed + pushed):
LicenseRef-proprietary stale markers (rp-s3 Cargo.toml, cockpit rpm/metainfo) → MIT;
identity package TODO license → real MIT; Runner.rc "All rights reserved" → MIT notice.
Clean bills: upstream MIT attribution chain, icon pack (vscode-material-icon-theme
5.35.0, MIT, LICENSE bundled in cockpit/assets/file_icons/), fonts (OFL via
google_fonts, banner rasterization exempt), no GPL/AGPL/SSPL/NC deps in any
subproject (per-direct-dep verified). Remaining licensing work is
binary-distribution-gated, not flip-gated: .work/backlog/backlog-licensing-binary-notices.md
(LGPL libmpv/FFmpeg notices + MPL dbus for cockpit binaries; licenses screen in both apps).

## Path decision (operator)

- **Option 1 — fresh public repo**: cleaned snapshot (squashed/shallow
  history) pushed to a new public repo; this repo stays private as the dev
  archive. Zero history risk, fast, preserves MIT attribution via
  LICENSE/NOTICE. RECOMMENDED.
- **Option 2 — flip this repo public**: requires `git filter-repo` to strip
  the private layer from all history (force-push; breaks dependabot PR refs
  + all clones), then tree cleanup. Heavier, riskier, same visual result.

## Child stories (tracked in .work/active/stories/)

1. `story-brand-icon-regen-sweep` — Pillow rasterizer → every launcher/favicon/
   banner PNG + site SVGs; hash-verify ≠ upstream; drop stale screenshot.
2. `story-brand-theme-replacement` — app_colors.dart (byte-identical to
   upstream) + cockpit theme → Phosphor Beacon; Space Mono via google_fonts;
   drop vestigial font stanzas. Depends on 1.
3. `story-brand-site-sync` — tokens → Tailwind vars, logo/favicon, wordmark,
   README hero, screenshot retake. Depends on 1 (screenshot on 2).

## Brand cascade implementation complete — 2026-08-15

The branding half is implemented and locally verified:

- `story-brand-icon-regen-sweep` — `done` (`99876cc0`): all app/cockpit/site
  assets regenerated from Constellation III, 33/33 upstream hashes differ.
- `story-brand-theme-replacement` — `done` (`970d74a`): mobile/Cockpit dual-mode
  tokens + Space Mono landed; analyzers green, app 874-test serialized suite and
  Cockpit 280-test concurrency-2 suite green. The concurrency-2 app suite still
  exposes an unrelated pre-existing sync-test isolation failure documented in
  the child body; its isolated test is green.
- `story-brand-site-sync` — `done` (`c07fa20`): Tailwind/CSS dual-mode tokens,
  Space Mono, canonical inline marks, README reference, lint and 18-route build
  green.

Bounded deviations are recorded in the child items: banner PNG uses the
approved Noto Sans Mono fallback because Space Mono is not installed on the VM;
the themed phone screenshot and device visual smoke await device UAT because no
phone is attached.

**Lifecycle boundary:** this feature intentionally remains active at `drafting`.
The branding cascade is complete, but choosing and executing the fresh-public-
repo versus history-rewrite path is operator-owned and was explicitly excluded
from this implementation drain. No public-flip/security work was attempted and
nothing was pushed.

Parked by operator 2026-08-14: components mockup layer
(.mockups/design-system/components.css + showcase) — run before any
redesigned-screen mocks, not needed for the asset/theme cascade.


## Verification (all stories)

- Hash-compare regenerated icons against upstream raw files (must differ).
- `git grep -lE "192\.168\.50|100\.106\.7|dev-vm|tailscale"` on exported
  tree → only benign hits (site docs links), zero infra.
- App + cockpit build/analyze green; site lint+build green.
