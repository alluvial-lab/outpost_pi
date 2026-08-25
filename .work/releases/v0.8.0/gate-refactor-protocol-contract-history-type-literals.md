---
id: gate-refactor-protocol-contract-history-type-literals
kind: story
stage: done
tags: []
parent: null
depends_on: []
release_binding: v0.8.0
gate_origin: refactor
created: 2026-08-25
updated: 2026-08-25
---

# Derive transcript history discriminators from generated protocol facts

## Library
protocol-contract

## Rule
handwritten-type-string

## Confidence
High

## Location
`pi-extension/src/session/transcript_projection.ts:79`

## Issue
`transcriptEventsToSessionHistory()` handwrites all six session-history wire discriminators (`user_input`, `agent_message`, `tool_request`, `tool_result`, `compaction`, and `error`) even though the generated protocol registry owns the same values.

## Impact
A schema rename or history-family change can leave the durable replay mapper compiling with stale wire strings, splitting live and replay protocol behavior.

## Fix
Generate or consume named session-history discriminator constants from `protocol.generated.ts` and build every projected history event from that canonical registry.

## Implementation
- Generated `SESSION_HISTORY_EVENT_DISCRIMINATORS` and replaced all six replay projection literals with the canonical registry in `pi-extension/src/session/transcript_projection.ts`.
