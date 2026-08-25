---
id: release-v0.5.0
kind: release
stage: released
tags: []
parent: null
depends_on: []
release_binding: v0.5.0
gate_origin: null
created: 2026-08-15
updated: 2026-08-15
---

# Release v0.5.0

Brand identity v2.0 (**Phosphor Beacon** / Constellation III / Space Mono)
across every surface, the **public flip** (history shred + redaction), and the
post-flip **dependency refresh** (dependabot drain resumed and finished).

## Provenance note (retroactive binding)

**The tag was cut before the substrate release flow ran.** `v0.5.0`
(ab938b41, 2026-08-15) shipped via a direct release commit; the five done
items were never bound, no release record or changelog entry existed, and the
gates never ran against the bundle. This record is a **manual retrofit**
(operator-approved path B): items stamped `release_binding: v0.5.0` and
collapsed here post-tag; the CHANGELOG entry added retroactively; the six
gates were then run post-hoc over the bundle **with all findings routed to
the next release** (nothing blocks a shipped tag). Post-tag hotfixes
(8a6feccd gradle wrapper commit, 6a72542b gradle tmpdir → VM-local
gradle.properties) are noted in the changelog but unbound — they bind to the
next release.

## Bound items (5)

| id | title | kind | git ref |
|----|-------|------|---------|
| story-brand-icon-regen-sweep | Icon regeneration sweep — Constellation III across every surface | story | 99876cc0 |
| story-brand-theme-replacement | App + cockpit theme replacement — Phosphor Beacon | story | 970d74a |
| story-brand-site-sync | Site sync — Phosphor Beacon + v2 mark | story | c07fa20 |
| story-public-flip-shred-runbook | Public flip: targeted history shred + content redaction runbook | story | 56a4be08 |
| story-dependabot-drain-resume | Resume and finish the dependabot drain | story | a7c643f8 |

Bundle = `git diff v0.4.0..v0.5.0`: 173 files, +5303/−3884.

### Binding-consistency warnings

`binding_guard: warn`, `epic_cohesion: phased` — 0 CONFLICTs, 1 INCOMPLETE
(informational under phased; not acted on):

- INCOMPLETE — `feature-public-flip-branding-and-exposure` (drafting,
  unbound) is the parent of 4 bound items. Deliberate operator lifecycle
  boundary: the branding cascade + flip shipped, while the feature body still
  carries residual operator-owned scope (device UAT for the themed
  screenshot/visual smoke; parked components-mockup layer). If that residual
  is judged done-in-substance, close the feature unbound rather than
  reopening it.

## Gate runs (post-hoc, 2026-08-15)

All six configured gates (`security, tests, cruft, docs, patterns, refactor`) ran
over the v0.5.0 bundle **after** the tag, per the operator's instruction:
findings are tracked for the **next** release, not blockers for this one
(nothing blocks a shipped tag). Raw findings (pre-dedupe): security 1H/1M/1L ·
tests 2H/4M · docs 2H/7M/1L · cruft 5 High-conf/1 decision-required ·
patterns 2 genuine (cataloged) · refactor 1 Medium-conf.

Deduped disposition (docs↔cruft overlaps merged):

- **4 active stories** (High → `stage: implementing`, unbound — next
  release's blocking set):
  `gate-security-release-workflow-action-pinning` (app-release.yml 3 +
  cockpit-release.yml 12 mutable refs holding signing/publish authority;
  sibling backlog item covers deps-audit/e2e-pairing),
  `gate-tests-concurrent-first-run-pairing-race`,
  `gate-tests-mobile-scanner-v7-boundary`,
  `gate-docs-agent-reference-refresh-post-v050` (stale version guidance +
  nonexistent push-docker workflow instruction across the skills surface).
- **2 pattern files written to the catalog**
  (`paired-brightness-semantic-palettes`,
  `canonical-mark-rasterization-fanout`) + 1 tracking backlog item for their
  drift risks.
- **12 backlog items** (medium/low + decision-required):
  postcss-override-vulnerable, e2e-log-tail-before-redaction,
  theme-dual-mode-contrast, site-light-dark-contract,
  brand-asset-export-matrix, cockpit-native-plugin-smoke,
  v050-doc-drift-batch (7 findings), wareframe-subsystem-decision
  (decision required), appearance-font-hints (user-visible copy),
  v050-dead-code-sweep, token-port-drift, cockpit-control-island.

Public-flip spot-check (security gate): current tree clean — no sensitive
pattern hits beyond benign site-docs links.

## Shipped items

Bodies retained on disk (retain-bodies) under `release_binding: v0.5.0` — see
Bound items table above for the five bodies in this directory.

_Shipped 2026-08-15 · mapping: tag-based · 5 items · retroactive binding · post-hoc gates_
