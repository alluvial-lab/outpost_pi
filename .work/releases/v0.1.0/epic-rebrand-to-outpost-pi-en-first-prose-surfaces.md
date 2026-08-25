---
id: epic-rebrand-to-outpost-pi-en-first-prose-surfaces
kind: feature
stage: done
tags: [rebrand, docs, i18n, prose]
parent: epic-rebrand-to-outpost-pi-en-first
depends_on: []
release_binding: v0.1.0
gate_origin: null
created: 2026-07-14
updated: 2026-07-15
---

# EN-first — cross-cutting prose surfaces (branding, docs, CLAUDE.md, config)

## Brief

Translate Portuguese → English in the cross-cutting prose surfaces that do
not belong to any single subproject's build gate: `branding/` SVG comment
prose + README, `docs/` foundation docs, the per-subproject `CLAUDE.md` files
that carry PT prose, and cockpit's non-Dart config/packaging files (YAML,
plist, metainfo XML, Swift, CHANGELOG). This is the "seam" feature — it owns
the files that fall between the by-subproject code slices so none are missed
or double-claimed.

No gap-fill work here: these are prose/config surfaces, not public APIs. The
doc-convention's Always tier does not apply (Skip tier: config, docs, READMEs).
The work is pure PT→EN translation of prose.

## Epic context
- Parent epic: `epic-rebrand-to-outpost-pi-en-first`
- Position in epic: independent cross-cutting slice. No `depends_on`. Owns
  the seam files so the parallel by-subproject features don't have to
  coordinate over shared docs. Can run in parallel with every other child
  feature.

## Foundation references
- `.agents/skills/documentation-conventions/SKILL.md` — Skip tier (config,
  docs, READMEs) confirms no gap-fill here; pure translation.
- Parent epic `## Grounded surface measurement` — branding (6), docs (1).
- Parent epic `## What this epic does NOT cover` — `scripts/` exclusion.

## Boundary with the external-surfaces epic

The external-surfaces epic (`epic-rebrand-external-surfaces`, `stage: review`)
already migrated the **wordmark and hostname text** in `branding/banner.svg`
(Outpost-Pi wordmark, npm command, `outpost-pi.kevoun.com` URL) via the
`story-...-branding-svg-redraw` story. That work is done. **This feature's
branding scope is the remaining PT** — SVG comment prose (e.g.
`<!-- Símbolo π -->`, `<!-- Bolinha azul característica -->`) and
`branding/README.md` (PT prose). Do not re-touch the wordmark/URL text nodes
already migrated. The design pass should grep `branding/` for accented Latin
to scope the exact remaining PT.

## Scope detail (measured)

- `branding/` — 6 files: `banner.svg`, `logo-{full,background,foreground,
  monochrome}.svg`, `README.md`. PT is SVG comment prose + README prose.
- `docs/` — 1 file: `docs/SPEC.md` (PT prose in a foundation doc).
- Per-subproject `CLAUDE.md` files carrying PT prose (e.g.
  `app/lib/config/CLAUDE.md`, `app/lib/routing/CLAUDE.md`, `app/lib/ui/CLAUDE.md`,
  `app/lib/domain/CLAUDE.md`, `app/lib/data/CLAUDE.md`, `cockpit/CLAUDE.md`,
  `cockpit/lib/app/CLAUDE.md`, `cockpit/lib/app/core/CLAUDE.md`). These are
  durable agent docs — EN is in scope.
- Cockpit non-Dart config/packaging: `cockpit/distribute_options.yaml`,
  `cockpit/packaging/README.md`, `cockpit/macos/**` (plist, entitlements,
  Swift), `cockpit/windows/**` (rc, inno template, yaml),
  `cockpit/linux/**` (metainfo xml, CMake, my_application.cc, packaging yaml),
  `cockpit/docs/rpc-protocol.md`, `cockpit/CHANGELOG.md`, `cockpit/pubspec.yaml`.
  Note: `cockpit/linux/work.jacobmoura.cockpit.metainfo.xml` carries the old
  applicationId in its filename — the *file rename* is owned by the first
  rebrand epic's mechanical-rename feature; this feature only translates the
  PT *content* inside it.

## What this feature does NOT cover
- `scripts/` shell comments — out of scope (operator glue; locked boundary).
- The wordmark/URL text in `branding/banner.svg` — already migrated by the
  external-surfaces epic.
- Generated/vendored state.
- Any `.dart`/`.ts`/`.rs`/`.tsx` source — owned by the by-subproject features.
- File renames (e.g. the `work.jacobmoura.cockpit.metainfo.xml` filename) —
  owned by the mechanical-rename feature.

## Verification
No build gate (prose/config only). Verify by grep: zero PT (accented Latin)
across `branding/`, `docs/`, the `CLAUDE.md` files, and cockpit non-Dart
config — excluding historical CHANGELOG entries that record the migration
(per the external-surfaces epic's CHANGELOG convention) and excluding
`scripts/`.

<!-- The design pass (`/agile-workflow:feature-design`) will fill in the
per-file translation plan and the CHANGELOG-historical-entry exclusion rule. -->

## Review (2026-07-15, standard, cross-model fresh-context)

Reviewer: `openai-codex/gpt-5.6-sol` (different model class from the umans
orchestrator). One balanced pass over the integrated feature diff
(`376fa38..HEAD -- branding/ docs/ cockpit/linux/`).

### Findings (adjudicated)
- **Important — missed ASCII-only Portuguese in Linux packaging** (`cockpit/linux/cockpit.desktop:5`): `Comment=Cliente desktop do Outpost-Pi — GUI multi-pane sobre o motor do Pi` was missed because the feature's verification used an accented-character scan only, which cannot catch ASCII PT. Translated to `Comment=Outpost-Pi desktop client — multi-pane GUI over the Pi engine`. **Fixed.** Sibling `metainfo.xml` and `make_config.yaml` were already English.
- No other findings.

### Verification of fixes
- Re-scan of `cockpit/linux/` for residual PT (accented + ASCII tokens) clean; only all-English strings remain.
- No build gate (`.desktop` is packaging metadata).

### Verdict
Approve. Advanced `review → done`.
