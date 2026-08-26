---
id: feature-cockpit-storage-json-vs-hive-repository-adapters
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

- [ ] In-memory-port tests cover settings, project CRUD/order/last selection,
      layout save/load/remove, and dismissed update version.
- [ ] Malformed project records remain ignored and malformed layout strings
      remain missing (`null`).
- [ ] No domain or UI file imports a JSON or Hive adapter.
- [ ] Public repository signatures and persisted key/value shapes do not change.

## Ordering constraint

Depends on `feature-cockpit-storage-json-vs-hive-storage-port-json-store` for
the storage port. It can proceed independently of the legacy exporter.
