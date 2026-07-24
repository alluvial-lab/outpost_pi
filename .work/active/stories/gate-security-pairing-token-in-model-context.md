---
id: gate-security-pairing-token-in-model-context
kind: story
stage: implementing
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
