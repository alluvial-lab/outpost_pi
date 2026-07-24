---
id: app-owner-key-version-rollback-hardening
kind: story
stage: implementing
tags: [app, security]
parent: feature-owner-identity-transition
depends_on: []
release_binding: null
gate_origin: null
created: 2026-06-28
updated: 2026-07-23
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
