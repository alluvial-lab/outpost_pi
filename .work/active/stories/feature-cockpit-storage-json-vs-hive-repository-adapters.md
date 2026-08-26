---
id: feature-cockpit-storage-json-vs-hive-repository-adapters
kind: story
stage: done
tags: [cockpit]
parent: feature-cockpit-storage-json-vs-hive
depends_on: [feature-cockpit-storage-json-vs-hive-storage-port-json-store]
release_binding: null
gate_origin: null
created: 2026-08-26
updated: 2026-08-26
---

# Replace repository adapters behind existing domain contracts

## Checkpoint

Implement the four JSON adapters from the parent feature's Unit 3:
`JsonSettingsStore`, `JsonProjectRepository`, `JsonWorkspaceLayoutStore`, and
`JsonDismissedUpdateStore`. Each receives only `StateStore`; domain/UI callers
remain on their existing repository contracts and see no backend type.

Preserve all existing keys, primitive map shapes, project ordering/defaults,
last-selection behavior, encoded-layout-string behavior, and corrupt-layout
recovery. Rewrite backend-specific domain comments so contracts no longer claim
Hive is their implementation.

## Acceptance evidence

- [x] In-memory-port tests cover settings, project CRUD/order/last selection,
      layout save/load/remove, and dismissed update version.
- [x] Malformed project records remain ignored and malformed layout strings
      remain missing (`null`).
- [x] No domain or UI file imports a JSON or Hive adapter.
- [x] Public repository signatures and persisted key/value shapes do not change.

## Implementation notes

Implemented inline by the same feature-owning `openai-codex/gpt-5.6-sol`
worker at `xhigh` effort after the state-store dependency reached `done`.
Migration was completed first per the caller's serialization order; repository
work then proceeded independently of bootstrap cutover.

Added `JsonSettingsStore`, `JsonProjectRepository`,
`JsonWorkspaceLayoutStore`, and `JsonDismissedUpdateStore`. Every adapter takes
only `StateStore`; public domain contracts, keys, primitive project-map shape,
manual ordering/defaults, last-selection behavior, encoded layout strings, and
dismissed-version semantics remain unchanged. Project parsing ignores records
without their required id/path boundary and retains the legacy defaults for
optional fields. Layout decoding still treats malformed or non-object JSON as
missing.

Backend-specific prose was removed from the touched domain contracts/entities.
A direct search confirms no `domain/` or `ui/` file imports a JSON or Hive
repository adapter. The live Hive adapters intentionally coexist until the
final dependent checkpoint changes composition and removes them; landing both
backends in parallel earlier would have expanded runtime risk without evidence.

## Verification

From `cockpit/` with the repository Flutter SDK and `PUB_CACHE`:

- `flutter analyze` — passed with zero issues.
- `flutter test` — passed, 313 tests.
- `test/core/data/json_repository_adapters_test.dart` uses an in-memory
  `StateStore` fake and proves settings defaults/full-shape round trip; project
  CRUD/order/last-selection/defaults/malformed-record filtering; layout
  encoded-string shape/save/load/remove/corruption recovery; and dismissed
  update semantics.
- Existing suites remained unchanged, including the independent bootstrap
  wiring assertion, which passed in the full run.

## Ordering constraint

Depends on `feature-cockpit-storage-json-vs-hive-storage-port-json-store` for
the storage port. It can proceed independently of the legacy exporter.
