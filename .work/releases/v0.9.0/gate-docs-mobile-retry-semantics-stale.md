---
id: gate-docs-mobile-retry-semantics-stale
kind: story
stage: done
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.9.0
gate_origin: docs
created: 2026-08-26
updated: 2026-08-26
---

# Mobile remote-coding skill still promises idempotent-or-rejected retries

## Drift category
repo-skill-staleness

## Location
- Doc: `.agents/skills/mobile-remote-coding/SKILL.md:57-66`
- Contradicting source: `PROTOCOL.md:338-347`; `app/lib/domain/contracts/owner_delivery_outbox.dart:3-23`

## Current doc text
> Every app action should be safe under retry and late arrival ... Make retry either idempotent or visibly rejected as duplicate/stale.

## Contradiction
The v0.9.0 owner-prompt contract is deliberately at-least-once across a hard session/process boundary. Same-session stable IDs collapse ordinary duplicates, but a successor-session retry can repeat intent; the encrypted room-scoped outbox retargets and removes entries only after target-session confirmation. The blanket retry rule would lead an agent to design exactly-once or duplicate rejection where the shipped contract permits repetition.

## Required edit
Replace the blanket retry assertion with the shipped split: require stable IDs and target binding; use same-session idempotency where available; use the encrypted outbox and authoritative room/session hydration for `delivery_retry`; state that hard-boundary recovery is at-least-once and may repeat intent.

## Closure (2026-08-26)

Updated `.agents/skills/mobile-remote-coding/SKILL.md` with stable-ID and
peer/room/session binding, same-session idempotency, encrypted outbox and
authoritative hydration for `delivery_retry`, and the at-least-once hard-boundary
caveat that a successor-session resend may repeat intent. Verified the shipped
contract at `PROTOCOL.md:338-351` and the outbox port at
`app/lib/domain/contracts/owner_delivery_outbox.dart:3-20`.
