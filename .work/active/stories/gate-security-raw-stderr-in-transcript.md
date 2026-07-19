---
kind: story
release_binding: null
parent: feature-redact-secrets-from-diagnostic-surfaces
stage: done
id: gate-security-raw-stderr-in-transcript
tags: []
depends_on: []
gate_origin: security
created: 2026-07-01
updated: 2026-07-18
---

# Raw child stderr is surfaced directly in the transcript

## Location
cockpit/lib/app/cockpit/ui/session/agent_session.dart:658

## Issue
Stderr from the spawned Pi process is displayed verbatim as a transcript side-channel, which can expose provider errors, local paths, or accidental secrets.

## Recommendation
Redact common secret patterns and/or show a generic diagnostic with a separate explicit copy raw details path for local troubleshooting.

## Design checkpoint

Replace `RpcDiagnostic.text` with a typed category (`childStderr` or
`streamReadFailure`) at the Cockpit process boundary. Project fixed transcript
text and deduplicate consecutive child-stderr rows; do not retain a hidden raw
buffer or add a raw-copy path.

Acceptance evidence:
- Non-empty stderr still creates a visible diagnostic fact, but its text cannot
  reach `InfoEntry` or the transcript.
- Stream read failures remain distinguishable without interpolating the raw
  error object.
- Blank stderr, process exit, and turn/lifecycle convergence retain current
  behavior.

## Implementation notes
- Execution capability: `openai-codex/gpt-5.6-sol` (caller-selected high reasoning for the security-sensitive cross-stack feature).
- Review weight: `standard` (caller default); child story review is not applicable.
- Files changed: `cockpit/lib/app/cockpit/data/rpc/pi_rpc_process.dart`, `cockpit/lib/app/cockpit/domain/entities/rpc_event.dart`, `cockpit/lib/app/cockpit/ui/session/agent_session.dart`, `cockpit/lib/app/cockpit/ui/session/agent_entry.dart`, `cockpit/tool/rpc_smoke.dart`, `cockpit/test/ui/agent_session_turn_projection_test.dart`.
- Tests added: opaque diagnostic projection, fixed text, severity distinction, and consecutive child-stderr deduplication.
- Simplification: replaced arbitrary `RpcDiagnostic.text` with the two-value `RpcDiagnosticKind` enum; no raw stderr/error buffer survives the process boundary.
- Discrepancies from design: updated the RPC smoke consumer to display the typed category because the domain contract intentionally removed diagnostic text.
- Adjacent issues parked: none.
- Verification: `flutter test --no-pub test/ui/agent_session_turn_projection_test.dart test/data/pi_rpc_process_control_test.dart` passed (22 tests).
