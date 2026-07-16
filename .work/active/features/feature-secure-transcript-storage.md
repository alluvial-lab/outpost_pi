---
id: feature-secure-transcript-storage
kind: feature
stage: drafting
tags: [app, security]
parent: null
depends_on: []
release_binding: null
gate_origin: security
created: 2026-07-15
updated: 2026-07-16
---

# App: secure and collision-safe durable transcript storage

## Brief

Two security gate findings describe the durable transcript Hive boxes on the
mobile app: distinct room/session identifiers can map to the same box name
(collision), and the boxes are opened as default (unencrypted) Hive boxes.
Together: messages from one session can be misattributed to another, and the
transcript is persisted in plaintext. This feature makes transcript storage
collision-safe and encrypted:

- `gate-security-transcript-box-name-collision` — distinct room/session identifiers map to the same transcript box name after sanitization
- `gate-security-transcript-boxes-unencrypted` — transcript event logs opened as default Hive boxes without an encryption cipher

## Simplification opportunity

Derive box names from a collision-free key (or namespace by room+session);
enable a Hive encryption cipher for transcript boxes. Behavior change: existing
unencrypted boxes are migrated or superseded on first launch after upgrade.

## Source

Promoted from backlog by `scope` (2026-07-15). 2
`gate-security-transcript-box-*` findings from the v0.6.0 release
`gate-security` pass.
