---
id: epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-ui
kind: feature
stage: drafting
tags: [rebrand, docs, i18n, cockpit]
parent: epic-rebrand-to-outpost-pi-en-first
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
---

# EN-first + dartdoc gap-fill — cockpit module: UI layer

## Brief

Translate Portuguese → English and adopt the dartdoc documentation framework
in the cockpit module's **UI layer** (`cockpit/lib/app/cockpit/ui/`):
viewmodels, widgets, session, states. 38 PT-bearing Dart files. This layer
holds the user-facing widgets and viewmodels — the slice most likely to
contain user-facing PT string literals (button labels, tooltips, error
messages) that need translation-review, not mechanical sed.

PT is predominantly comment prose, but the design pass must identify and
review any user-facing string literals (the cockpit-wide count is ~18 PT
string literals; a subset live in this layer). Gap-fill scope is the Always
tier: ViewModel exports, exported widgets with non-obvious contracts. Per the
doc convention, exported Flutter widgets with 3+ params are Recommended
(should have a doc comment), not Always.

## Epic context
- Parent epic: `epic-rebrand-to-outpost-pi-en-first`
- Position in epic: one of three layer-slices of the cockpit module. Sibling
  slices: `...-cockpit-domain`, `...-cockpit-data`. No `depends_on` between
  the three layers — disjoint file sets, shared build gate. Can run in
  parallel.

## Foundation references
- `.agents/skills/documentation-conventions/SKILL.md` — dartdoc `///` format;
  Always tier (ViewModel exports) vs Recommended tier (exported widgets with
  3+ params).
- `.agents/skills/flutter-desktop-cockpit/SKILL.md` — cockpit code reference.
- `.agents/skills/scan-documentation/SKILL.md` — gate self-check.
- Parent epic `## Decomposition risks` — "user-visible UI text needs review,
  not just mechanical translation" applies most directly to this slice.

## What this feature does NOT cover
- The cockpit module's `domain/` and `data/` layers — sibling features.
- Wire-stable identifiers — owned by the first rebrand epic.
- `scripts/` shell comments — out of scope.
- Generated/vendored state.

## Verification
```bash
# from cockpit/
flutter analyze && flutter test
```
## Test files in scope

1 cockpit UI test file carries PT: `cockpit/test/ui/terminal_input_test.dart`
(PT in both comments and test descriptions like `test('começa inativo', ...)`
— the latter are user-facing in test output and need translation-review, not
sed). Tests are Skip-tier for gap-fill (per the doc convention).

Plus a grep confirming zero PT (accented Latin) in
`cockpit/lib/app/cockpit/ui/` and `cockpit/test/ui/`.

<!-- The design pass (`/agile-workflow:feature-design`) will fill in the
ViewModel/widget export audit, the comment-vs-UI-string split, and the
gap-fill list. -->
