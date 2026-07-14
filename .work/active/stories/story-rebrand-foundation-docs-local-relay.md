---
id: story-rebrand-foundation-docs-local-relay
kind: story
stage: review
tags: [rebrand, docs]
parent: epic-rebrand-external-surfaces
depends_on: []
release_binding: null
gate_origin: review
created: 2026-07-14
updated: 2026-07-14
---

# Roll foundation docs forward to local-relay-only + dormant rp-s3

## Brief

Phase 8 review finding B4. Foundation docs still describe the retired
operating model (public relay, active rp-s3 publication, native self-update).
Per the rolling-foundation principle, persistent docs are current-state —
they must reflect local-relay-only and dormant rp-s3.

## Scope (from review B4)

- `docs/VISION.md:83-85` — refers to "the public relay."
- `docs/DECISIONS.md:58,122-123,132` — public relay decision, active rp-s3
  publication gate, enabled native self-update model.
- `docs/ARCHITECTURE.md:133-140` — says site manifests come from rp-s3,
  describes it as an active proxied server.
- `docs/SPEC.md:16` — describes rp-s3 as a container serving Cockpit
  installers without noting dormant status.

`PROTOCOL.md` was checked — no community-default resolution contract to fix
(review rejected that concern).

## Acceptance criteria

- [x] No foundation doc describes a public/community relay as a current
  capability.
- [x] rp-s3 is documented as dormant / not currently deployed.
- [x] No "previously" / historical migration prose (rolling-foundation rule).
- [x] Native self-update docs reflect the no-op default.

## Implementation notes

- Rewrote the listed foundation-doc surfaces in place to state the current
  local-relay-only deployment, dormant `rp-s3` status, and native self-update
  no-op default.
- Updated the deferred federation wording to use the local relay as the
  current reference point, removing the retired public-relay assumption.
- Rationale: the durable docs must describe the operating model that is
  deployed now, while retaining only the source-level `rp-s3` description
  needed to identify the dormant component. `PROTOCOL.md` was left unchanged
  because review B4 found no community-default resolution contract there.

## Verification

- Searched `docs/` for public/community relay, `rp-s3`, self-update, and
  historical-migration wording; current-state references now match the
  acceptance criteria.
- `git diff --check` passes.
