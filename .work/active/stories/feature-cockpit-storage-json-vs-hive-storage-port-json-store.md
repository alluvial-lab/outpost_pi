---
id: feature-cockpit-storage-json-vs-hive-storage-port-json-store
kind: story
stage: done
tags: [cockpit]
parent: feature-cockpit-storage-json-vs-hive
depends_on: []
release_binding: v0.9.0
gate_origin: null
created: 2026-08-26
updated: 2026-08-26
---

# Define the state-store port and atomic JSON adapter

## Checkpoint

Introduce the single storage boundary selected by the parent design:
`StateStore`/`StateStoreFactory` contracts in core domain and a factory-owned,
versioned `JsonStateStore` adapter in core data. The adapter loads missing or
malformed state as empty, coalesces mutations, serializes commits, and writes a
same-directory temporary file with flush + bounded rename retry. The factory,
not repositories or UI, owns instance reuse and `flushAll()`.

Exact paths, signatures, and error behavior are specified in the parent
feature's Unit 1. Do not wire repositories or bootstrap in this checkpoint.

## Acceptance evidence

- [x] Port-boundary tests cover round-trip, idempotent open, delete,
      debounce/coalescing, serialized snapshots, and multi-store flush.
- [x] Missing, malformed, and unsupported envelopes open empty and remain
      writable without throwing during open.
- [x] Atomic replacement produces a complete `{"version":1,"data":...}`
      envelope and leaves no temporary file after success.
- [x] Domain contracts import no filesystem, Flutter widget, Hive, or JSON
      implementation type.

## Implementation notes

Implemented inline with `openai-codex/gpt-5.6-sol` at `xhigh` effort, as
specified by the autopilot caller for this corruption-sensitive migration. One
feature owner retains all Cockpit storage context; no subagent adapter was
available, so no story-level fanout was used.

`StateStore` and `StateStoreFactory` now form the domain-owned boundary.
`JsonStateStoreFactory` owns path-scoped instance reuse and `flushAll()`, while
`JsonStateStore` validates JSON-compatible mutations, coalesces bursts, and
serializes complete version-1 snapshots through a flushed same-directory temp
file plus bounded atomic-rename retry. Failed writes propagate to their mutation
future; `flush()` retries a dirty newest snapshot rather than claiming success.

Tolerant reads preserve evidence: empty, malformed, invalid-envelope, and
unsupported-version files are moved to a non-destructive `.corrupt[.N]`
quarantine before the empty writable store is exposed. Diagnostics are closed,
content-free categories with no payload or local path. If quarantine itself
fails, startup can still read defaults, but writes fail closed instead of
overwriting the only recovery evidence.

`path` became a direct dependency with the port adapter because production path
construction starts in this unit. The existing unrelated generated-plugin
working-tree changes were preserved and excluded from the commit.

## Verification

From `cockpit/` with the repository Flutter SDK and `PUB_CACHE`:

- `flutter analyze` — passed with zero issues.
- `flutter test` — passed, 300 tests.
- `test/core/data/json_state_store_test.dart` proves round-trip/idempotent open,
  coalescing, delete, multi-store flush, explicit async write serialization,
  complete atomic replacement with no stale temp, quarantine-and-recovery for
  every tolerant-read class, absent-file behavior, write-failure propagation,
  and invalid-value rejection.
- The unchanged bootstrap wiring test
  `bootstrap wiring catches exhausted store retries without an unhandled throw`
  passed in the full suite.
