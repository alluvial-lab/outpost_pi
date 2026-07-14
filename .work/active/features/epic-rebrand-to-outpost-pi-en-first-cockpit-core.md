---
id: epic-rebrand-to-outpost-pi-en-first-cockpit-core
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

# EN-first + dartdoc gap-fill — cockpit core module

## Brief

Translate Portuguese → English and adopt the dartdoc documentation framework
in the cockpit `core` module — the shared foundation (cross-cutting domain,
data, UI, utils, routes, env). 54 PT-bearing Dart files: `core/domain` (15),
`core/data` (16), `core/ui` (17), plus `core/utils`, `core/routes.dart`,
`core/env.dart`, `core/app_intents.dart`, `core/core_module.dart`.

PT is overwhelmingly comment prose (the cockpit-wide ratio is ~2,100 PT
comment-lines vs ~18 string literals). Gap-fill scope is the Always tier per
the doc convention: exported Dart classes/functions from shared/domain
layers, service-layer functions, `Result`/`Either`-returning functions,
ViewModel exports. The `core/domain/contracts/` and `core/domain/entities/`
surfaces are the contract-bearing areas most likely to need gap-fill.

## Epic context
- Parent epic: `epic-rebrand-to-outpost-pi-en-first`
- Position in epic: independent mid-large slice. No `depends_on` — the
  cockpit's wire-stable identifiers (control-RPC discriminator) already
  migrated in the first rebrand epic. Can run in parallel with every other
  child feature. Shares the cockpit build gate (`flutter analyze` + `flutter
  test`) with the other cockpit features, but the file sets are disjoint.

## Foundation references
- `.agents/skills/documentation-conventions/SKILL.md` — dartdoc `///` format
  and the Always tier for Dart.
- `.agents/skills/flutter-desktop-cockpit/SKILL.md` — cockpit code reference;
  read before editing `cockpit/`.
- `.agents/skills/scan-documentation/SKILL.md` — gate self-check.
- Parent epic `## Grounded surface measurement` — the 54-file count for core.

## Edge case: generated file

`cockpit/lib/app/core/ui/file_icons/file_icon_map.g.dart` is a generated file
(`// GENERATED — do not edit by hand.`) whose header comment carries PT
("Mapeamento arquivo/pasta -> ícone..."). It is **shipped** (lives in `lib/`,
not in the epic's excluded generated/vendored dirs), so its PT is in scope for
translation. However it is **generated** (Skip tier for gap-fill — do not add
dartdoc to its internals). The design pass should: translate the header
comment to EN (one-time edit; the generator source is a script, out of scope
per the `scripts/` exclusion, so it will not be regenerated in this epic), and
skip gap-fill on the generated body. See parent epic `## Design decisions`.

## What this feature does NOT cover
- Wire-stable identifiers (control-RPC discriminator) — owned by the first
  rebrand epic, already shipped.
- Product-identity string renames — owned by the mechanical-rename feature.
- `scripts/` shell comments — out of scope (operator glue).
- Generated/vendored state (`.dart_tool/`, build output).

## Verification
```bash
# from cockpit/
flutter analyze && flutter test
```
## Test files in scope

4 root-level cockpit test files carry PT and test core/DI/factory wiring:
`cockpit/test/widget_test.dart`, `cockpit/test/lsp_pool_di_test.dart`,
`cockpit/test/core_factories_resolve_test.dart`,
`cockpit/test/feature_resolves_core_upward_test.dart`. Tests are Skip-tier for
gap-fill (per the doc convention); the only work is PT→EN translation of
comments and test descriptions (the latter are user-facing in test output and
need translation-review, not sed).

Plus a grep confirming zero PT (accented Latin) in `cockpit/lib/app/core/`
and the 4 root-level `cockpit/test/*.dart` files.

<!-- The design pass (`/agile-workflow:feature-design`) will fill in the
Always-tier export audit (sub-planned by layer: domain/data/ui), the
generated-file edge-case handling, and the gap-fill list. -->
