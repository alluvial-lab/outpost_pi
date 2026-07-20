---
id: gate-docs-app-v0-2-0-changelog-missing
kind: story
stage: implementing
tags: [app, documentation]
parent: null
depends_on: []
release_binding: app-v0.2.0
gate_origin: docs
created: 2026-07-20
updated: 2026-07-20
---

# Add the missing app-v0.2.0 changelog entry

## Drift category
changelog-gap

## Location
- Doc: `CHANGELOG.md:12`
- Release evidence: `app/lib/data/local/boxes.dart:1-7`, `app/lib/ui/chat/chat_page.dart:74-86`, `app/lib/domain/session_state.dart:341-357`

## Current doc text
> `CHANGELOG.md` begins its current release notes with `## [relay-0.2.0] — 2026-07-20`; it has no `app-v0.2.0` section.

## Contradiction
Eleven app-attributed items are bound to `app-v0.2.0`, including encrypted transcript storage and migration, lifecycle-owned connection/sync/mesh work, and chat status, resume-hydration, and transcript-order resilience. The changelog's stated purpose is to document all notable Outpost-Pi changes, but it has no release entry that records this component release.

## Required edit
Add an `app-v0.2.0` section to `CHANGELOG.md` that accurately summarizes the shipped secure transcript storage/migration, lifecycle ownership, and chat-resilience changes. Keep it as current release notes; do not add historical or progress prose.
