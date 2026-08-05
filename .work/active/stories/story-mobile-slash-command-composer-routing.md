---
id: story-mobile-slash-command-composer-routing
kind: story
stage: drafting
tags: [app]
parent: feature-mobile-slash-command-invocation
depends_on: [story-mobile-slash-command-extension-action]
release_binding: null
gate_origin: null
created: 2026-08-04
updated: 2026-08-04
---

# App composer /-routing (mode 2)

Unit C of `feature-mobile-slash-command-invocation` — one of the two operator-
decided entry modes. Route `/`-prefixed composer input as a command, not a prompt.

## Change

- `app/lib/ui/chat/**` (composer send) + `app/lib/data/**` (routing) — when the
  user sends a `/`-prefixed string from the composer, route it to the
  `slash_command` action (Unit B) instead of `sendMessage` (which prompt-injects
  via `_wakeAgent` and bypasses pi's command parser — the root cause).
- Bare/unknown commands still go to the parser (pi surfaces the error).

## Acceptance

- [ ] Typing `/reload` in the mobile composer → pi reloads (NOT sent to the agent
      as a literal prompt).
- [ ] Non-`/` input unchanged (still a normal agent prompt).
- [ ] Relevant `flutter test --exclude-tags e2e` green; `flutter analyze` clean.

## Ordering

`depends_on: [story-mobile-slash-command-extension-action]` (needs the action).
Parallel with D.
