---
id: gate-refactor-protocol-contract-sync-agent-message-literal
kind: story
stage: done
tags: []
parent: null
depends_on: []
release_binding: v0.3.0
gate_origin: refactor
created: 2026-07-20
updated: 2026-07-24
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

## Implementation discovery

First worker bounce (2026-07-23) was an orchestrator scope error, not a design
flaw: the adjacent replay identity path is `app/lib/data/sync/session_history_replay.dart`
(matching two `agent_message` literals at ~:75), which the first brief wrongly
excluded from write scope. Scope corrected on re-dispatch. Note: generated
`AgentMessage.type` is an instance getter and generated dispatch uses switch
literals, so the canonical-value shape must accommodate that (single handwritten
const consumed by all four call sites, ideally bound to `AgentMessage.type` by a
drift-guard test).

## Implementation notes

- Changed `app/lib/data/sync/session_history_replay.dart` and
  `app/lib/data/sync/sync_service.dart` so all four transcript-identity call
  sites use `agentMessageWireType`, declared alongside `serverReplayEventId` /
  `serverReplayMessageId`.
- Added the generated-contract drift guard in
  `app/test/data/sync/session_history_replay_test.dart`; it compares the
  constant with `const AgentMessage(inReplyTo: '', text: '').type`.
- Verification: focused replay test passed; `flutter analyze` passed with no
  issues; full `flutter test` completed with 814 passing tests and only the six
  known e2e failures caused by unavailable pairing-endpoint environment.

## Review

Bounded inline review (orchestrator, 2026-07-23): diff inspected — single
`agentMessageWireType` const beside the identity helpers, all four call sites
substituted, drift-guard test binds it to generated `AgentMessage.type`.
Minimal diff, no generated files touched. Approved -> done.
