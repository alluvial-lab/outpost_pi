---
id: story-rebrand-foundation-docs-local-relay
kind: story
stage: drafting
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

- [ ] No foundation doc describes a public/community relay as a current
  capability.
- [ ] rp-s3 is documented as dormant / not currently deployed.
- [ ] No "previously" / historical migration prose (rolling-foundation rule).
- [ ] Native self-update docs reflect the no-op default.
