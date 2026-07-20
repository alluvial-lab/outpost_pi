---
kind: story
release_binding: v0.2.0
parent: feature-relay-resource-bounds
stage: done
id: gate-security-subscription-empty-target-retention
tags: [security]
depends_on: []
gate_origin: security
created: 2026-07-01
updated: 2026-07-20
---

# Subscription target map retains empty target entries

## Severity
Medium

## Location
relay/src/subscriptions.rs:54

## Issue
remove_all removes the subscriber from each target set but never deletes now-empty target keys, allowing repeated subscribe/replace calls with new target names to grow memory indefinitely.

## Recommendation
Remove subscribers_of entries when their set becomes empty and consider bounding peer-id length / total subscription churn per connection.

## Implementation notes
- Execution capability: `openai-codex/gpt-5.6-sol` (caller-selected for security-critical relay work).
- Review weight: `standard` (caller default; feature-level review only).
- Files changed: `relay/src/subscriptions.rs`.
- Tests added: thousand-cycle replacement churn at the existing 64-target boundary plus partial/disconnect cleanup retained-key assertions.
- Simplification: `remove`, `remove_all`, and replacement now share one reverse-edge deletion rule.
- Discrepancies from design: none.
- Adjacent issues parked: none.
- Verification: focused subscription tests passed.
