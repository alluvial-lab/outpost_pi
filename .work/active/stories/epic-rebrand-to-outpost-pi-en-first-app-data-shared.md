---
id: epic-rebrand-to-outpost-pi-en-first-app-data-shared
kind: story
stage: implementing
tags: [rebrand, docs, i18n, app]
parent: epic-rebrand-to-outpost-pi-en-first-app
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
---

# Translate app data/shared prose and document service seams

## Scope

Own `app/lib/config/**`, `app/lib/data/**`, `app/lib/pairing/**`,
`app/lib/routing/**`, and `app/lib/main.dart`. Translate only these nine fixed
PT-bearing files; use the rest of the boundary solely for the reviewed
Always-tier dartdoc gap-fill.

- `app/lib/config/CLAUDE.md`
- `app/lib/config/utils/injector.dart`
- `app/lib/data/CLAUDE.md`
- `app/lib/data/update/secure_dismissed_update_store.dart`
- `app/lib/data/update/update_checker_impl.dart`
- `app/lib/data/update/url_launcher_opener.dart`
- `app/lib/pairing/qr_scanner.dart`
- `app/lib/routing/CLAUDE.md`
- `app/lib/routing/adaptive.dart`

PT in this story is comment/prose-only. Never alter quoted literals, wire
identifiers, storage keys, URLs, generated protocol output, or product identity
as part of translation.

## Dartdoc gap manifest

Add meaningful EN `///` docs to the exact declarations/members listed in the
parent feature under `## Always-tier dartdoc audit` → `Data/service and shared
application seams`. The manifest covers:

- DI/bootstrap/resume lifecycle (`config/dependencies.dart`, `main.dart`).
- Actions, image, Hive, preferences, read repositories, session gate/history,
  sync, channel/connection, relay/WS, speech-plugin, pairing/storage, and
  selection service contracts.
- Discriminated-union/error-returning boundaries and functions whose failure,
  ownership, identity, or teardown behavior is not obvious from the signature.

Adapter overrides inherit documented interface behavior; add adapter-specific
doc only where behavior differs. Exclude generated DTOs, schema-only records,
constructors, fields, test-only debug seams, barrels, and trivial accessors not
named by the parent manifest.

## Acceptance criteria

- [ ] All nine fixed PT-bearing files are natural EN.
- [ ] Every declaration/member in the parent's data/shared gap manifest has
      intent-level adjacent `///` documentation.
- [ ] No runtime literal, identifier, signature, storage key, URL, or protocol
      constant changes.
- [ ] No changes under `app/lib/domain/**` or `app/lib/ui/**`.
- [ ] Touched Dart files are formatted; targeted service/transport tests pass.
- [ ] The feature-level integrated run can pass `flutter analyze` and
      `flutter test` from `app/`.
