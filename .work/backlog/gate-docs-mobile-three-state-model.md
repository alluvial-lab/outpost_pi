---
id: gate-docs-mobile-three-state-model
created: 2026-08-28
updated: 2026-08-28
tags: [documentation]
release_binding: null
gate_origin: docs
---

# Mobile remote-coding checklist omits the distinct orchestrating state

## Drift category
repo-skill-staleness

## Location
- Doc: `.agents/skills/mobile-remote-coding/SKILL.md:30-39,81-99`
- Contradicting source: `app/lib/domain/session_state.dart:405-420`; `app/lib/ui/chat/chat_page.dart:732-748`; `protocol/schema/relay-control.schema.json:43-46`

## Current doc text
> For every user-visible remote session, model `connected idle`, `working` (agent turn or compaction), `reconnecting`, `offline`, and `stale/unknown` distinctly; the phone should answer “Is it working?”

## Contradiction
The checklist's working-state model predates the independent room-level `background` axis. The app now distinguishes idle, turn-working, and background `orchestrating…` presentation, with turn status taking precedence and composer/cancellation remaining turn-scoped. The checklist's verification matrix likewise covers idle/working but not the new background-work state.

## Required edit
Extend the state model and UX/verification guidance with the independent `orchestrating` state backed by `RoomMeta.background`. Preserve the existing reconnect/stale rules and explicitly keep background work separate from turn-scoped cancellation and composer gating.
