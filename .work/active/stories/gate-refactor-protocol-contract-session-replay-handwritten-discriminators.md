---
id: gate-refactor-protocol-contract-session-replay-handwritten-discriminators
kind: story
stage: implementing
tags: []
parent: null
depends_on: []
release_binding: v0.3.0
gate_origin: refactor
created: 2026-07-24
updated: 2026-07-24
---

# Transcript replay duplicates generated history discriminators

## Library
protocol-contract

## Rule
handwritten-type-string

## Confidence
High

## Location
`app/lib/data/sync/session_history_replay.dart:56`

## Issue
Replay mapping handwrites generated history types such as user_input, tool_request, tool_result, compaction, and agent_message, including the new agentMessageWireType mirror.

## Fix
Pass each generated event's event.type into identity helpers and remove agentMessageWireType; extend Dart codegen with named discriminator constants only where no typed instance is available.
