---
id: gate-refactor-protocol-contract-session-replay-handwritten-discriminators
kind: story
stage: done
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

## Implementation notes

- Changed history replay identity construction to pass each generated event's
  `event.type`; removed its handwritten `agentMessageWireType` mirror.
- Extended the Dart IR/codegen with an explicitly requested generated named
  discriminator for the live `AgentMessage` path, where no event instance is
  available. The regenerated protocol exports `agentMessageWireType` for that
  existing live identity consumer.
- Regenerated `app/lib/protocol/generated/protocol.g.dart` with
  `node tools/protocol-codegen/bin/protocol-codegen.mjs --target dart --schema tools/protocol-codegen/fixtures/app_pi_client_dart_ir.json --out app/lib/protocol/generated/protocol.g.dart`.
- Verification: focused replay test (9 passing) and Dart protocol-codegen tests
  (11 passing). `flutter analyze` was blocked by an unrelated concurrent
  warning in `test/pairing/owner_identity_bridge_test.dart`; the broad
  `flutter test test/data` run has two unrelated existing sync-service failures,
  while the touched replay and generated-contract suites pass.

## Review

Bounded inline review (orchestrator, 2026-07-24): generator-first fixes with
regenerated output committed together; discriminators now derive from the
schema (SERVER_MESSAGE_DISCRIMINATORS / generated Dart constant via
discriminatorConstantName with duplicate validation); isFiniteNumber emits
conditionally. Codegen/multiplexer/replay tests green; earlier sync-test
noise was cross-worker mid-flight contamination (suite green on integrated
tree). Approved -> done.
