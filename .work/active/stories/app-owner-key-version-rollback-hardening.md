---
id: app-owner-key-version-rollback-hardening
kind: story
stage: done
tags: [app, security]
parent: feature-owner-identity-transition
depends_on: []
release_binding: app-v0.3.0
gate_origin: null
created: 2026-06-28
updated: 2026-07-25
---

# Harden app owner-key mesh version rollback handling

Low-confidence adversarial finding: resetting mesh version watermark to zero after owner-key changes may allow older valid signed blobs to be reaccepted in restore/confusion scenarios. Investigate whether a highest-ever-version per owner key is needed.

## Investigation result (feature-design 2026-07-23)

CONFIRMED, upgraded from low-confidence: `_lastVersion` is in-memory only
(cold start ⇒ `since=null` full fetch) and `_applyVerified` has no
version-monotonicity check, so an untrusted relay can serve any historical
validly-signed blob — a rollback that reintroduces a revoked peer. The durable
per-owner highest-version watermark IS warranted. Exact design (persistence
shape, fail-closed semantics, publish flooring, owner-hash scoping, acceptance
criteria) is Unit 1 of the parent feature body.

## Implementation notes

- Added the distinct `dev.outpostpi.meshwatermark` secure-storage namespace;
  `wipeAll()` deliberately retains its per-owner entries.
- `MeshSyncService` now lazily loads the owner-scoped high-water mark, fails
  pulls/publishes closed when it is unavailable, rejects signed rollbacks with
  `mesh_rollback_rejected`, and persists forward movement after verified apply
  and publish. Publishing starts at `max(lastVersion, highWatermark) + 1`.
- Added rollback cold-start, owner-scope/wipe retention, fail-closed,
  fresh-publish-floor, and `allowEmpty` advancement coverage.
- Verification: `flutter analyze` passed; focused mesh/storage tests passed
  (45 tests). Full `flutter test` ran with only the six documented unavailable
  pairing-endpoint e2e failures.
