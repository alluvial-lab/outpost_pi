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

## Path decision (operator)

- **Option 1 — fresh public repo**: cleaned snapshot (squashed/shallow
  history) pushed to a new public repo; this repo stays private as the dev
  archive. Zero history risk, fast, preserves MIT attribution via
  LICENSE/NOTICE. RECOMMENDED.
- **Option 2 — flip this repo public**: requires `git filter-repo` to strip
  the private layer from all history (force-push; breaks dependabot PR refs
  + all clones), then tree cleanup. Heavier, riskier, same visual result.

## Child stories (spawn on implement)

1. `story-brand-icon-redesign` — new mark + palette direction (operator picks
   from drafts); regenerate: Android adaptive set, iOS AppIcon, cockpit
   macOS set + Windows .ico, favicon; sync site logos from branding source;
   update branding/README.md version note.
2. `story-app-theme-brand-palette` — replace upstream-identical
   app_colors.dart with brand-derived semantic palette; align cockpit theme;
   drop vestigial font stanzas.
3. `story-public-repo-sanitized-snapshot` — build the cleaned export
   (exclude private layer via .public-export ignorelist, verify zero
   infra-string hits with the audit greps, push to new public repo, flip
   README/social preview/banner).
4. `story-site-screenshot-refresh` — retake branding screenshot(s) post
   rebrand; update site cockpit page.

## Verification (all stories)

- Hash-compare regenerated icons against upstream raw files (must differ).
- `git grep -lE "192\.168\.50|100\.106\.7|dev-vm|tailscale"` on exported
  tree → only benign hits (site docs links), zero infra.
- App + cockpit build/analyze green; site lint+build green.
