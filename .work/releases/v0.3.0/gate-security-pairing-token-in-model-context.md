---
id: gate-security-pairing-token-in-model-context
kind: story
stage: done
tags: [security]
parent: null
depends_on: []
release_binding: v0.3.0
gate_origin: security
created: 2026-07-24
updated: 2026-07-24
---

# Pairing bearer token enters model context

## Severity
High

## Domain
Secrets & Configuration / Data Protection

## Location
`pi-extension/src/extension/command_surface/pairing_coordinator.ts:106`

## Evidence
The QR URI containing the raw pairing token is rendered through `pi.sendMessage`. Pi custom messages are persisted and participate in LLM context, so the next model request during the token's 60-second default (10-minute max) lifetime exposes the bearer token to the model provider. A provider or downstream context processor that can reach the relay can generate an Owner identity, compute pair_mac, submit a valid signed-DH request, and obtain a persistent authenticated owner channel.

## Remediation direction
Render pairing material through a TUI-only mechanism such as appendEntry plus a registered renderer, or a transient UI component. Add a regression proving assembled model context and session custom messages never contain the token or URI.

## Implementation notes

- Replaced the persistent `sendMessage` pair-code payload with a `ctx.ui.custom()` TUI-only pairing dialog; non-TUI modes refuse QR display before issuing a token.
- Added regression coverage that renders a live token while modeling `sendMessage` as a context-building sink, then proves neither the pairing URI nor token appears in custom messages or assembled model context.
- Verification: `./node_modules/.bin/tsc --noEmit`; `./node_modules/.bin/vitest run` (55 files, 929 passed, 3 skipped); `./node_modules/.bin/tsc` build.

## Review

Bounded inline review (orchestrator, 2026-07-24): diff inspected. @throws
contracts match throwing exports. Pairing QR/token moved from context-persisted
pi.sendMessage to a TUI-only ctx.ui.custom dialog (non-TUI mode gets a
token-free warning); regression proves token/URI absent from custom messages
and assembled model context. Full extension suite green (929 passed, 3
skipped) + typecheck + build. Approved -> done.
