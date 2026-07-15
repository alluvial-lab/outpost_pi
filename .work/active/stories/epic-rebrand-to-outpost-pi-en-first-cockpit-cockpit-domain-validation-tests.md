---
id: epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-domain-validation-tests
kind: story
stage: done
tags: [rebrand, docs, i18n, cockpit]
parent: epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-domain
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-15
---

# Translate cockpit domain validation, value objects, and tests

## Scope

Translate Portuguese comment prose to English in:

- `cockpit/lib/app/cockpit/domain/validators/worktree_name_validator.dart`
- `cockpit/lib/app/cockpit/domain/value_objects/semver.dart`
- `cockpit/lib/app/cockpit/domain/value_objects/update_target.dart`

Translate Portuguese test descriptions, comments, and natural-language fixture
prose through deliberate review (not blind replacement) in:

- `cockpit/test/domain/worktree_name_validator_test.dart`
- `cockpit/test/domain/update_info_test.dart`
- `cockpit/test/domain/semver_test.dart`
- `cockpit/test/domain/workspace_pane_test.dart`

Tests are Skip-tier for dartdoc: translate their user-visible test output and
prose, but do not add API documentation. Preserve validation order and error
enums, semver behavior, and every assertion. A natural-language fixture value
may be translated only with its same-file expectation updated to the equivalent
English value; protocol-like fixture keys and values remain unchanged.

## Acceptance criteria

- [x] Portuguese comments in the three production files are idiomatic English dartdoc/non-doc commentary with contract meaning preserved.
- [x] Portuguese test/group descriptions, comments, and natural-language fixture prose in the four listed tests are idiomatic English and still describe the asserted behavior.
- [x] No production executable code, runtime string, public signature, validator ordering, semver behavior, or value-object semantics change.
- [x] No assertion is weakened, deleted, skipped, or broadened; fixture-value translation remains behavior-neutral and paired with its exact expectation.
- [x] Tests receive no gap-fill dartdoc, consistent with the Skip tier.
- [x] A targeted accented-Latin grep reports no matches in the seven owned files, and a manual lexical review catches unaccented Portuguese residue.
- [x] `dart format` is run on the owned files; the four targeted domain tests pass, then from `cockpit/`, `flutter analyze` and `flutter test` pass (or an exact environment failure is reported without weakening tests).

## Implementation notes

- Files changed: `cockpit/lib/app/cockpit/domain/validators/worktree_name_validator.dart`, `cockpit/lib/app/cockpit/domain/value_objects/semver.dart`, `cockpit/lib/app/cockpit/domain/value_objects/update_target.dart`, and the four scoped files under `cockpit/test/domain/`.
- Tests added: none; existing test descriptions, comments, and behavior-neutral fixture prose were translated without changing coverage or assertions.
- Discrepancies from design: none. The natural-language fixtures `resumo` and `unico-1` were translated to `summary` and `unique-1` with their exact paired expectations, while protocol-shaped keys and values remained unchanged.
- Documentation gap-fill: added intent-bearing dartdoc for the validator result/constructors/getter, validation contract, semver comparison contract, and update-target constructor and fields; test files remained Skip-tier.
- Verification: scoped `dart format`; four targeted domain test files (39 tests) passed; `flutter analyze` reported no issues; full `flutter test` passed (241 tests); accented-Latin grep and manual lexical review found no Portuguese residue in the owned paths.
- Adjacent issues parked: none.
