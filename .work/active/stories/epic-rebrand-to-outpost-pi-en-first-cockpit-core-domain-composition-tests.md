---
id: epic-rebrand-to-outpost-pi-en-first-cockpit-core-domain-composition-tests
kind: story
stage: done
tags: [rebrand, docs, i18n, cockpit]
parent: epic-rebrand-to-outpost-pi-en-first-cockpit-core
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-15
---

# Translate cockpit core domain/composition prose and fill contract dartdoc

Translate Portuguese prose in the core domain, root composition/util files,
and four root tests. Add EN `///` only to the nine named Always-tier gaps.
Preserve behavior, signatures, DI wiring, identifiers, routes, commands,
fixtures, and test assertions.

## Owned files

### Domain (16)

- `cockpit/lib/app/core/domain/contracts/disposable.dart`
- `cockpit/lib/app/core/domain/contracts/environment_probe.dart`
- `cockpit/lib/app/core/domain/contracts/lsp_client.dart`
- `cockpit/lib/app/core/domain/contracts/pairing_gateway.dart`
- `cockpit/lib/app/core/domain/contracts/revoke_gateway.dart`
- `cockpit/lib/app/core/domain/contracts/service.dart`
- `cockpit/lib/app/core/domain/contracts/settings_store.dart`
- `cockpit/lib/app/core/domain/contracts/system_permissions.dart`
- `cockpit/lib/app/core/domain/contracts/usecase.dart`
- `cockpit/lib/app/core/domain/entities/app_settings.dart`
- `cockpit/lib/app/core/domain/entities/lsp_diagnostic.dart`
- `cockpit/lib/app/core/domain/entities/pair_event.dart`
- `cockpit/lib/app/core/domain/entities/setup_check.dart`
- `cockpit/lib/app/core/domain/exceptions/lsp_error.dart`
- `cockpit/lib/app/core/domain/exceptions/relay_error.dart`
- `cockpit/lib/app/core/domain/result.dart`

### Composition and utilities (5)

- `cockpit/lib/app/core/app_intents.dart`
- `cockpit/lib/app/core/core_module.dart`
- `cockpit/lib/app/core/env.dart`
- `cockpit/lib/app/core/routes.dart`
- `cockpit/lib/app/core/utils/executable_resolver.dart`

### Root tests (4)

- `cockpit/test/widget_test.dart`
- `cockpit/test/lsp_pool_di_test.dart`
- `cockpit/test/core_factories_resolve_test.dart`
- `cockpit/test/feature_resolves_core_upward_test.dart`

## Gap-fill inventory

Add intent/contract dartdoc to:

1. `Disposable.dispose` — explicit resource teardown contract.
2. `LspClientFactory.create` — fresh client and spec/root ownership.
3. `PairingGatewayFactory.create` — fresh ephemeral pairing attempt.
4. `RevokeGateway.revoke` — `Result` success/failure and timeout behavior.
5. `RevokeGatewayFactory.create` — fresh ephemeral revoke gateway.
6. `Success` — successful `Result` branch meaning.
7. `Failure` — failed `Result` branch meaning.
8. `CheckStatusX` — setup-gate projection purpose.
9. `resolveExecutable` — platform search/fallback contract.

In `executable_resolver.dart`, separate the currently adjacent intent prose so
`resolveExecutable` owns meaningful dartdoc. Do not add docs to test helpers,
DTO-only shapes, trivial members, or overrides that inherit a documented
contract.

## Implementation notes

- Translated existing comments/dartdoc in context while preserving LSP/JSON-RPC,
  Flutter Modular, Result, lifecycle, route, and command vocabulary.
- Translated only comments and test descriptions in the four tests; assertions
  and fixtures are unchanged.
- Included `contracts/disposable.dart` despite its original sentence containing
  no accented characters, and made no writes outside the owned file set while
  the data and UI stories ran in parallel.
- Files changed: all 16 listed domain files, the five listed composition/utility
  files, and the four listed root tests.
- Tests added: none; this is a behavior-preserving documentation and test-label
  translation pass.
- Rationale: rewrote plan-history phrasing as current-state contract prose where
  needed, and split executable availability prose from the
  `resolveExecutable` platform/fallback contract so dartdoc attaches to the
  declaration it documents.
- Discrepancies from design: none.
- Adjacent issues parked: none.
- Verification: repository-local `flutter analyze` passed with zero issues;
  the full `flutter test` suite passed (241 tests); the four owned root tests
  passed both focused and full-suite runs; accented-PT and manual lexical scans
  over all owned files found no remaining Portuguese prose.

## Acceptance criteria

- [x] All 25 owned files contain no Portuguese prose or PT test descriptions.
- [x] The nine named gaps have meaningful EN `///` comments that explain intent
      and contracts rather than restating types.
- [x] No gap-fill is added to generated code, tests, DTO-only shapes, trivial
      helpers, or inherited implementation overrides.
- [x] Public signatures, DI graph, route constants, executable resolution,
      Result behavior, fixtures, and test assertions are unchanged.
- [x] From `cockpit/`, the four owned root tests pass with the repository-local
      Flutter toolchain.
