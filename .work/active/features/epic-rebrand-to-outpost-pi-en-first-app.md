---
id: epic-rebrand-to-outpost-pi-en-first-app
kind: feature
stage: drafting
tags: [rebrand, docs, i18n, app]
parent: epic-rebrand-to-outpost-pi-en-first
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
---

# EN-first + dartdoc gap-fill — app

## Brief

Translate Portuguese → English and adopt the dartdoc documentation framework
in `app/` (Flutter mobile). 21 PT-bearing files under `app/lib/` (0 in tests).
PT is predominantly comment prose; the few user-facing string literals
(onboarding `welcome_step.dart`, update-banner copy) need translation-review,
not mechanical sed — the design pass must distinguish the two.

Covers `app/lib/` only. Gap-fill scope is the Always tier per the doc
convention: exported Dart classes/functions from shared/domain layers,
ViewModel exports, service-layer functions, `Result`/`Either`-returning
functions. The app's `domain/contracts/` and `domain/value_objects/` are the
contract-bearing surfaces most likely to need gap-fill.

## Epic context
- Parent epic: `epic-rebrand-to-outpost-pi-en-first`
- Position in epic: independent mid-size slice. No `depends_on` — the app's
  wire-stable identifiers (auth string, applicationId) already migrated in the
  first rebrand epic. Can run in parallel with every other child feature.

## Foundation references
- `.agents/skills/documentation-conventions/SKILL.md` — dartdoc `///` format
  and the Always tier for Dart (exported declarations, ViewModel exports,
  `Result`-returning functions).
- `.agents/skills/flutter-mobile/SKILL.md` — app code reference; read before
  editing `app/`.
- Parent epic `## Grounded surface measurement` — the 21-file count (the
  first rebrand epic's "~23" estimate holds).
- Parent epic `## Decomposition risks` — "user-visible UI text needs review,
  not just mechanical translation" applies here (onboarding/update copy).

## What this feature does NOT cover
- Wire-stable identifiers (auth string, applicationId) — owned by the first
  rebrand epic's wire-stable migration feature, already shipped.
- Product-identity string renames — owned by the mechanical-rename feature.
- `scripts/` shell comments — out of scope (operator glue).
- Generated/vendored state (`.dart_tool/`, `.pub-cache/`, build output).

## Verification
```bash
# from app/
flutter analyze && flutter test
```
Plus a grep confirming zero PT (accented Latin) in `app/lib/`.

<!-- The design pass (`/agile-workflow:feature-design`) will fill in the
Always-tier export audit, the comment-vs-UI-string split, and the gap-fill
list. -->
