---
kind: story
release_binding: null
parent: feature-redact-secrets-from-diagnostic-surfaces
stage: implementing
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
