---
id: epic-durable-transcript-ownership-retire-rederivation
kind: feature
stage: drafting
tags: [pi-extension, refactor]
parent: epic-durable-transcript-ownership
depends_on: [epic-durable-transcript-ownership-durable-event-log, feature-canonical-transcript-timestamp-ownership, epic-durable-transcript-ownership-durable-native-events]
release_binding: null
gate_origin: null
created: 2026-08-25
updated: 2026-08-25
---

# F4 — Retire SDK-message re-derivation + two-source contract

## Brief

Remove the lossy re-derivation path; formalize SDK-messages-vs-extension-entries
(LLM-context vs transcript) as the documented consistency contract with a
reconciliation test surface. Terminal feature — lands last, after F1-F3 prove
durable coverage.

## Epic context

Depends on F1 (foundation), F2 (timestamp migration), F3 (native events) —
retirement is only safe when durable coverage is complete.

## Simplification opportunity

IS the simplification: deletes the re-derivation code path and its
divergence-prone reconciliation, replacing it with a narrow documented
boundary. Black-box refactor (transcript output identical when durable data
is complete).
