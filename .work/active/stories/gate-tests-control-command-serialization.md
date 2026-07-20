---
kind: story
release_binding: v0.2.0
parent: feature-cockpit-settings-control-tests
stage: done
id: gate-tests-control-command-serialization
tags: [testing]
depends_on: []
gate_origin: testing
created: 2026-07-01
updated: 2026-07-20
---

# Control-command serialization test only samples one relay action

## Location
cockpit/lib/app/cockpit/data/rpc/pi_rpc_process.dart:405

## Issue
AC uncovered: Control commands from Cockpit are emitted as schema command envelopes. (bound item: epic-bold-generated-protocol-cockpit-control-rpc-step-3)

## Recommendation
Parameterize pi_rpc_process_control_test.dart across relay_on, relay_off, relay_toggle, relay_status, and add an empty-rename failure assertion.

## Implementation notes
- Execution capability: `openai-codex/gpt-5.6-sol` (caller-selected; bounded protocol-adapter test matrix).
- Review weight: `standard` (caller default); review is feature-level because this is a child checkpoint.
- Files changed: `cockpit/test/data/pi_rpc_process_control_test.dart`.
- Tests added/removed: parameterized the relay-control test across all four actions and added an empty/whitespace rename rejection case; preserved rename success and every UI-response variant.
- Simplification: one explicit action-to-wire oracle and one decode helper replace repeated per-action test bodies.
- Verification: `PUB_CACHE=/home/agent/projects/outpost_pi/.pub-cache flutter test --no-pub test/data/pi_rpc_process_control_test.dart` — 6 tests passed in the concurrent working tree (4 control tests plus 2 independently added diagnostics tests).
- Discrepancies from design: the story frontmatter remained at `drafting` despite the delegated caller identifying it as `implementing`; completed evidence advanced it directly to `done`. The test file also contained concurrent metadata-diagnostic coverage, which was preserved but excluded from this story commit.
- Adjacent issues parked: none.
