---
id: feature-fresh-session-shutdown-and-recoverable-delivery
kind: feature
stage: drafting
tags: [pi-extension, app, lifecycle]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-25
updated: 2026-08-25
---

# Fresh-session shutdown + recoverable-delivery contract

## Brief

Formed by groom (2026-08-25) from two backlog items that name each other:
`backlog-new-session-teardown-session-shutdown` (extension: the fresh-session
handshake should await normal lifecycle/resource drains instead of a
fixed-delay exit) and `backlog-recoverable-delivery-resend-contract`
(app+extension: quiesce → no SDK delivery during teardown → reconnect →
recovery proof; "Pairs with" the former).

One coherent capability: `/new` (mobile-initiated fresh session) must shut
down cleanly under load — draining in-flight delivery, releasing rooms and
locks deterministically — and any message the owner sends across the
boundary must be resend-recoverable, never lost. Evidence anchors: the
2026-08-23 restart-wrapper incident (marker + /quit with no wrapper) and
the swallow-fix lineage (6d1cbad6) both touch this boundary.

## Source items (absorbed — full bodies in git history + archive)

- backlog-new-session-teardown-session-shutdown
- backlog-recoverable-delivery-resend-contract

## Next

feature-design pass when picked up.
