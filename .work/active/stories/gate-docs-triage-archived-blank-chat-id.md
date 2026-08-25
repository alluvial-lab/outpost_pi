---
id: gate-docs-triage-archived-blank-chat-id
kind: story
stage: done
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.8.0
gate_origin: docs
created: 2026-08-25
updated: 2026-08-25
---

# Debug-capture triage still emits the archived blank-chat work item as live

## Drift category
readme-staleness

## Location
- Doc: `scripts/debug_capture_triage.py:34,388-389,470-471`
- Contradicting source: `.work/archive/backlog-app-blank-chat-direct-open.md:1-4`; `.work/releases/v0.7.0/story-fix-app-blank-chat-direct-open.md:88-94`

## Current doc text
> `BLANK_CHAT_TRACKING_ID = "backlog-app-blank-chat-direct-open"`
>
> `BLANK CHAT signature: ... [backlog-app-blank-chat-direct-open]`

## Contradiction
`backlog-app-blank-chat-direct-open` is archived as groom-done after its fix shipped. The current triage tool still labels a detected blank-chat signature with that retired item id, directing operators to a non-live work item and making a cured finding appear open.

## Required edit
Remove the archived tracking id from current triage output. Keep the generic blank-chat signature, or point it only at a current active item when one exists; never emit a groomed/archived id as live ownership.

## Implementation
- Removed the archived blank-chat tracking id from summary and timeline output in `scripts/debug_capture_triage.py`.
