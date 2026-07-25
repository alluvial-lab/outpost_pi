---
id: gate-tests-owner-transition-failure-paths-real-marker
kind: story
stage: implementing
tags: [testing]
parent: null
depends_on: []
release_binding: v0.3.0
gate_origin: tests
created: 2026-07-24
updated: 2026-07-24
---

# Owner-transition failure paths are not proven against the real marker

## Priority
High

## Value evidence
Item: `gate-security-owner-transition-committed-before-durable-cleanup` — a
release-blocking isolation contract: every cleanup failure must retain the
durable marker and keep identity access gated. The router success test
overrides `completePendingTransition`, while the transcript-failure test uses
a fake bridge that returns `IdentityReady` on retry; neither proves real
marker/identity behavior after disconnect, transcript, or marker-deletion
failure.

## Gap type
e2e-seam

## Suggested test
Drive `BootState` or the router with a real `OwnerIdentityBridge` and fake
secure storage. Inject failures after pairing wipe, during
disconnect/transcript wipe, and while deleting the transition marker. For
each, assert boot failure, marker retained,
`currentIdentity`/`currentOwnerPk == null`, `requireKeyPair` rejected, and a
subsequent clean retry commits exactly once.

## Test location (suggested)
`app/test/routing/app_router_test.dart`
