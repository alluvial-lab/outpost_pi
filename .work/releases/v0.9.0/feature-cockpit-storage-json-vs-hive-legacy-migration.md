---
id: feature-cockpit-storage-json-vs-hive-legacy-migration
kind: story
stage: done
tags: [cockpit]
parent: feature-cockpit-storage-json-vs-hive
depends_on: [feature-cockpit-storage-json-vs-hive-storage-port-json-store]
release_binding: v0.9.0
gate_origin: null
created: 2026-08-26
updated: 2026-08-26
---

# Add storage paths and one-shot Hive export

## Checkpoint

Implement `CockpitStoragePaths` and `LegacyHiveMigrator` as designed in the
parent feature's Unit 2. Keep debug/production separation, move the Windows JSON
default out of Documents/OneDrive into Application Support, retain current
Documents placement on macOS/Linux, and normalize paths with `package:path`.

Before any JSON store opens, export the four known legacy boxes (`settings`,
`window_state`, `projects`, `layouts`) independently into atomic version-1 JSON
envelopes. Normalize dynamic map keys recursively, preserve source files, and
write `migration.json` last. A failed box becomes an empty destination recorded
in the marker/diagnostics without preventing successful boxes from migrating.
Fresh installs receive a no-source marker.

## Acceptance evidence

- [x] Representative values for all four boxes survive with their existing key
      and value shapes.
- [x] A second run skips without rewriting JSON after the marker exists.
- [x] One failed/corrupt box is isolated and recorded while other boxes migrate.
- [x] Source `.hive` files remain untouched, and an interrupted marker-less run
      can rerun safely.
- [x] Path tests cover Windows Application Support selection and Windows/native
      separator normalization without claiming a real Windows smoke.

## Implementation notes

Implemented inline by the feature-owning `openai-codex/gpt-5.6-sol` worker at
`xhigh` effort after the state-store checkpoint reached `done`. The unavailable
subagent adapter did not change ownership or verification; this migration and
the next repository checkpoint remain serialized in one Cockpit context.

`CockpitStoragePaths` keeps `cockpit-debug`/`cockpit` separation, selects
Application Support for Windows JSON state, retains Documents on macOS/Linux,
and builds every location with `package:path`. The deterministic legacy search
prefers the currently shipped Documents location, then Application Support,
with normalized de-duplication. `path_provider` became a direct dependency in
the checkpoint that first imports it.

`LegacyHiveMigrator` searches for the first candidate containing a known box,
exports only existing source files, normalizes nested dynamic-map keys
recursively, and writes each of the four destinations through the state store's
single canonical envelope encoder and atomic writer. Each opened Hive box is
closed independently. A read/encode failure produces an empty destination plus
a fixed store/category diagnostic and a `failedStores` marker entry while the
other boxes continue. The source path and payload/error text are never logged or
persisted.

The marker is the last atomic write. Existing markers skip Hive and all JSON
rewrites; marker-less interrupted runs replay from preserved source state.
Fresh installs write only a `source: none` marker and create JSON stores lazily.
All legacy `.hive` files remain present as recovery evidence.

## Verification

From `cockpit/` with the repository Flutter SDK and `PUB_CACHE`:

- `flutter analyze` — passed with zero issues.
- `flutter test` — passed, 308 tests.
- Seeded real Hive fixtures prove all four stores, nested-map normalization,
  encoded-layout-string preservation, and source-file retention.
- Idempotency evidence: the test replaces migrated `projects.json` with a probe,
  runs the migrator a second time, observes `ran == false`, and proves the probe
  was not rewritten. A separate marker-less replay test proves interrupted work
  is safely rebuilt from the unchanged Hive source.
- Partial-failure evidence: an unencodable Hive layout value isolates only
  `layouts`, records it in both the result and marker, emits the closed
  diagnostic, and leaves migrated projects intact.
- Pure Windows-path tests prove Application Support selection, backslash
  normalization, and de-duplication without claiming a Windows runtime smoke.
- The independent bootstrap wiring test remained unchanged and passed in the
  full suite.

## Ordering constraint

Depends on `feature-cockpit-storage-json-vs-hive-storage-port-json-store` for
the canonical envelope and atomic-write primitive.
