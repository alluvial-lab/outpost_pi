---
id: feature-cockpit-storage-json-vs-hive-legacy-migration
kind: story
stage: implementing
tags: [cockpit]
parent: feature-cockpit-storage-json-vs-hive
depends_on: [feature-cockpit-storage-json-vs-hive-storage-port-json-store]
release_binding: null
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

- [ ] Representative values for all four boxes survive with their existing key
      and value shapes.
- [ ] A second run skips without rewriting JSON after the marker exists.
- [ ] One failed/corrupt box is isolated and recorded while other boxes migrate.
- [ ] Source `.hive` files remain untouched, and an interrupted marker-less run
      can rerun safely.
- [ ] Path tests cover Windows Application Support selection and Windows/native
      separator normalization without claiming a real Windows smoke.

## Ordering constraint

Depends on `feature-cockpit-storage-json-vs-hive-storage-port-json-store` for
the canonical envelope and atomic-write primitive.
