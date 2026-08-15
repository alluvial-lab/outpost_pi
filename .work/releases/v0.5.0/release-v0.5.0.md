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
(70328dbe, 2026-08-15) shipped via a direct release commit; the five done
items were never bound, no release record or changelog entry existed, and the
gates never ran against the bundle. This record is a **manual retrofit**
(operator-approved path B): items stamped `release_binding: v0.5.0` and
collapsed here post-tag; the CHANGELOG entry added retroactively; the six
gates were then run post-hoc over the bundle **with all findings routed to
the next release** (nothing blocks a shipped tag). Post-tag hotfixes
(a82e9fa1 gradle wrapper commit, b5b0e558 gradle tmpdir → VM-local
gradle.properties) are noted in the changelog but unbound — they bind to the
next release.

## Bound items (5)

| id | title | kind | git ref |
|----|-------|------|---------|
| story-brand-icon-regen-sweep | Icon regeneration sweep — Constellation III across every surface | story | 56bcbcd |
| story-brand-theme-replacement | App + cockpit theme replacement — Phosphor Beacon | story | 970d74a |
| story-brand-site-sync | Site sync — Phosphor Beacon + v2 mark | story | c07fa20 |
| story-public-flip-shred-runbook | Public flip: targeted history shred + content redaction runbook | story | b8350ab6 |
| story-dependabot-drain-resume | Resume and finish the dependabot drain | story | db1f9172 |

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

All six configured gates (`security, tests, cruft, docs, patterns, refactor`)
ran over the v0.5.0 bundle **after** the tag, per the operator's instruction:
findings are tracked for the **next** release, not blockers for this one
(nothing blocks a shipped tag). Findings and dispositions are recorded in the
gate-finding items (`gate_origin: <gate>`, `release_binding: null`) and the
summary below.

## Shipped items

Bodies retained on disk (retain-bodies) under `release_binding: v0.5.0` — see
Bound items table above for the five bodies in this directory.

_Shipped 2026-08-15 · mapping: tag-based · 5 items · retroactive binding · post-hoc gates_
