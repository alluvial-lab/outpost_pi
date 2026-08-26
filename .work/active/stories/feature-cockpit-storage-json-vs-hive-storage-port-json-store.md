---
id: feature-cockpit-storage-json-vs-hive-storage-port-json-store
kind: story
stage: implementing
tags: [cockpit]
parent: feature-cockpit-storage-json-vs-hive
depends_on: []
release_binding: null
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

- [ ] Port-boundary tests cover round-trip, idempotent open, delete,
      debounce/coalescing, serialized snapshots, and multi-store flush.
- [ ] Missing, malformed, and unsupported envelopes open empty and remain
      writable without throwing during open.
- [ ] Atomic replacement produces a complete `{"version":1,"data":...}`
      envelope and leaves no temporary file after success.
- [ ] Domain contracts import no filesystem, Flutter widget, Hive, or JSON
      implementation type.
