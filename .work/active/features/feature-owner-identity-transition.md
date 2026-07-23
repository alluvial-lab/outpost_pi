---
id: feature-owner-identity-transition
kind: feature
stage: drafting
tags: [security, app, pi-extension]
parent: null
depends_on: [feature-owner-message-e2e-authentication]
release_binding: null
gate_origin: security
created: 2026-07-23
updated: 2026-07-23
---

# Owner-identity transition boundary

## Brief

Two findings define the same security boundary — what happens when the owner
key changes (rotation, reset, or device replacement):

1. `app-owner-key-version-rollback-hardening` — after owner-key changes,
   older valid signed blobs may be reaccepted (no durable version watermark).
2. `gate-security-owner-reset-retains-transcripts` — owner-key replacement
   leaves the previous owner's transcripts readable (no namespace/wipe).

The design pass should decide as one contract: a durable mesh-version/owner
watermark (reject blobs signed before the latest transition), transcript
namespacing or wipe on owner change, and the recovery UX when a legitimate
owner loses key access. Deciding them separately risks two half-policies that
contradict at the boundary.

Depends on `feature-owner-message-e2e-authentication`: that feature's
per-pairing/session key derivation determines what owner rotation must
invalidate, so sequencing avoids re-deciding rotation semantics twice. The
two features together form the v0.3.0 owner-channel security arc.

## Simplification opportunity

A single owner-transition event with well-defined invalidation semantics
(keys, transcripts, cached memberships) replaces per-surface ad-hoc reset
handling.

## Origin

Groom 2026-07-23, cluster F7 — promoted per advisor-review recommendation
that it pairs with the owner-channel E2E authentication feature.
