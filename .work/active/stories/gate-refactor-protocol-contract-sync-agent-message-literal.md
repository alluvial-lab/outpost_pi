---
id: gate-refactor-protocol-contract-sync-agent-message-literal
kind: story
stage: implementing
tags: []
parent: null
depends_on: []
release_binding: null
gate_origin: refactor
created: 2026-07-20
updated: 2026-07-20
---

# Derive transcript identity discriminator from the generated protocol contract

## Library
protocol-contract

## Rule
handwritten-type-string

## Confidence
High

## Location
`app/lib/data/sync/sync_service.dart:981`

## Issue
The live transcript identity path writes the `agent_message` wire discriminator twice by hand even though the generated Dart protocol registry and `AgentMessage.type` already define that value, allowing wire renames to drift from live/replay deduplication identity.

## Fix
Expose or consume a generated canonical discriminator for `AgentMessage` and pass that single value to both `serverReplayEventId` and `serverReplayMessageId`; update the adjacent replay identity path to consume the same generated value rather than maintaining another literal.
