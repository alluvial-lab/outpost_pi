---
id: gate-patterns-v050-token-port-drift
created: 2026-08-15
updated: 2026-08-15
tags: [branding, workflow]
---

# v0.5.0 pattern candidates: token-port + mark-geometry drift risks

Post-hoc v0.5.0 patterns-gate output. Two genuine patterns were written to
the catalog (`.agents/skills/patterns/paired-brightness-semantic-palettes.md`,
`canonical-mark-rasterization-fanout.md`); their recorded drift risks are the
actionable residue:

1. **Hand-maintained token ports** — `tokens.css` is ported by hand into app
   and cockpit Dart with duplicated literal assertions and no shared
   cross-surface fixture; any contract change risks silent per-surface drift.
   Direction: generate or golden-test the ports against the contract
   (overlaps `gate-tests-theme-dual-mode-contrast`).
2. **Triple-encoded mark geometry** — Constellation III is encoded in Python
   (`scripts/generate-brand-assets.py:19-56`), canonical SVG
   (`branding/`, declared source of truth in `branding/README.md:4-5`), and
   independently in `site/src/app/opengraph-image.tsx:37-46`. Direction:
   single-source the geometry (parse the SVG in the rasterizer, or generate
   the OG image from the same source).
