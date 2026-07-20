---
kind: story
release_binding: v0.2.0
parent: feature-cockpit-async-action-ownership
stage: done
id: gate-refactor-lifecycle-unguarded-async-agent-composer
tags: []
depends_on: []
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-20
---

# Agent composer drops session operation futures

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Location
cockpit/lib/app/cockpit/ui/widgets/agent_composer.dart:322,325,496,560,887,918,1233

## Issue
Several async session/drop/control operations are invoked without await, return, or unawaited, so failures and lifecycle ordering are implicit.

## Fix
Needs analysis: await where ordering matters; otherwise wrap in unawaited(...) and ensure the callee catches/reports errors.

## Implementation

Applied the shared owned-async adapter to built-in commands, send/stop, native drop, attachment/paste callbacks, model/thinking selection, and relay control. Composer input still clears before image normalization and RPC completion, while every session operation is invoked exactly once and retains existing projection-based error behavior.

Verification: `flutter test test/ui/agent_session_turn_projection_test.dart` and `flutter analyze lib test` passed.
