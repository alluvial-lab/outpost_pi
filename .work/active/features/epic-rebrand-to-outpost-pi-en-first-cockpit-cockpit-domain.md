---
id: epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-domain
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

# EN-first + dartdoc gap-fill — cockpit module: domain layer

## Brief

Translate Portuguese → English and adopt the dartdoc documentation framework
in the cockpit module's **domain layer** (`cockpit/lib/app/cockpit/domain/`):
contracts, entities, validators, value_objects. 43 PT-bearing Dart files. This
is the contract-bearing heart of the cockpit module — the surface where
gap-fill matters most (contracts, `Result`-returning functions, domain
entities).

PT is comment prose. Gap-fill scope is the Always tier: exported Dart
classes/functions from the domain layer, `Result`/`Either`-returning functions,
contract interfaces. The `domain/contracts/` directory (e.g.
`worktree_manager.dart`) is the primary gap-fill target.

## Epic context
- Parent epic: `epic-rebrand-to-outpost-pi-en-first`
- Position in epic: one of three layer-slices of the cockpit module (the
  largest module, 103 files, split by layer to keep each design pass
  manageable). Sibling slices: `...-cockpit-ui`, `...-cockpit-data`. No
  `depends_on` between the three layers — disjoint file sets, shared build
  gate. Can run in parallel.

## Foundation references
- `.agents/skills/documentation-conventions/SKILL.md` — dartdoc `///` format
  and the Always tier for Dart domain/contract surfaces.
- `.agents/skills/flutter-desktop-cockpit/SKILL.md` — cockpit code reference.
- `.agents/skills/scan-documentation/SKILL.md` — gate self-check.
- Parent epic `## Grounded surface measurement` and `## Decomposition risks`
  (cockpit is 216/252 files; the module is sub-sliced by layer).

## What this feature does NOT cover
- The cockpit module's `ui/` and `data/` layers — sibling features.
- Wire-stable identifiers — owned by the first rebrand epic.
- `scripts/` shell comments — out of scope.
- Generated/vendored state.

## Verification
```bash
# from cockpit/
flutter analyze && flutter test
```
## Test files in scope

4 cockpit domain test files carry PT: `cockpit/test/domain/`
(`worktree_name_validator_test.dart`, `update_info_test.dart`,
`semver_test.dart`, `workspace_pane_test.dart`). Tests are Skip-tier for
gap-fill (per the doc convention); the only work is PT→EN translation of
comments and test descriptions (the latter are user-facing in test output and
need translation-review, not sed).

Plus a grep confirming zero PT (accented Latin) in
`cockpit/lib/app/cockpit/domain/` and `cockpit/test/domain/`.

<!-- The design pass (`/agile-workflow:feature-design`) will fill in the
Always-tier contract/entity export audit and the gap-fill list. -->
