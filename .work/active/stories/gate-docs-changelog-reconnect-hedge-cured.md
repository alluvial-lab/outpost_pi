---
id: gate-docs-changelog-reconnect-hedge-cured
kind: story
stage: implementing
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.8.0
gate_origin: docs
created: 2026-08-25
updated: 2026-08-25
---

# CHANGELOG keeps the cured reconnect-hedge issue under Unreleased known issues

## Drift category
changelog-gap

## Location
- Doc: `CHANGELOG.md:13-19`
- Contradicting source: `c1969a45`; `app/lib/data/transport/connection_manager.dart:837-920`

## Current doc text
> **Reconnect hedge gaps** ... the 3s fallback does not cover handshake-complete/auth-stalled attempts ... and a late fallback auth can supersede the adopted channel ... Fix scoped: `story-fix-app-reconnect-hedge-auth-boundary-and-post-adoption-cancel`.

## Contradiction
Commit `c1969a45` shipped the auth-read hedge and atomic loser-close fix in this release. The entry describes a current known defect and a scoped fix even though the implementation now cancels and awaits superseded attempts before adopting a channel.

## Required edit
Remove this cured issue from `[Unreleased]` and record it under the `v0.8.0` `Fixed` section. Do not leave a live known-issue claim or a future-looking fix-scope note.
