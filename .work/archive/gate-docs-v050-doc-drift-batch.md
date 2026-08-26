---
id: gate-docs-v050-doc-drift-batch
created: 2026-08-15
updated: 2026-08-26
tags: [docs, branding]
status: folded
folded_into: feature-doc-drift-repair (groom 2026-08-26)
---

# Post-v0.5.0 documentation drift batch (7 findings)

Post-hoc v0.5.0 docs-gate sweep (batched per the v0.4.0 doc-drift-batch
precedent). All verified against the tree 2026-08-15.

1. **Changelog assigns two releases to `v0.5.0`** (Medium) —
   `CHANGELOG.md:589` `## [v0.5.0] — 2026-06-29 (repo)` (pre-rebrand
   historical) collides with the tagged `:12` `## [v0.5.0] — 2026-08-15`.
   Disambiguate the historical heading (e.g. `v0.5.0 (pre-rebrand, 2026-06-29)`).
2. **"Space Mono everywhere" overclaims** (Medium) — `CHANGELOG.md:14` +
   `branding/README.md:38` vs the Noto Sans Mono banner fallback in
   `scripts/generate-brand-assets.py:167-168` (bounded deviation recorded in
   `story-brand-theme-replacement`). Qualify the claim or regenerate with
   Space Mono.
3. **Root README "Official site — TBD"** (Medium) — `README.md:16`; site is
   established (`site/README.md:22`, `pi-extension/README.md:11`). Point it at
   `https://outpost-pi.kevoun.com`.
4. **Dark-only assertions contradict dual-mode reality** (Medium; docs+cruft
   dup) — `site/README.md:32` "Dark-only theme";
   `.agents/skills/next-site/SKILL.md:81` "globals.css owns the dark
   palette"; `cockpit/lib/app/core/ui/file_icons/file_icon_map.g.dart:9`
   "Cockpit is dark-only" comment. Describe system-following dual-mode;
   narrow the icon comment to the icon set.
5. **Six skill descriptions call the product "Remote Pi"** (Medium) —
   `.agents/skills/{pi-extension-typescript,flutter-mobile,flutter-desktop-cockpit,rust-relay,next-site,code-design-principles}/SKILL.md:3`.
   Rename current-product prose to Outpost-Pi; keep "Remote Pi" only for
   provenance/history/source handles.
6. **DECISIONS.md "origin is the only configured remote"** (Medium) —
   `docs/DECISIONS.md:41-43` vs the configured fetch-only provenance remote
   (`.git/config:14-17`). State the durable policy: origin is the only
   *push* target (matches `AGENTS.md:13`).
7. **release-uat.md See-also retired locations** (Low) — `docs/release-uat.md:67-68`
   links the pairing suite under `.work/active/features/` (now
   `.work/releases/v0.2.0/feature-cross-component-e2e-pairing-suite.md`) and
   names a nonexistent AGENTS section; point at durable surfaces, name
   "Paired wire changes".
