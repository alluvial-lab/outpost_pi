---
id: gate-docs-debug-log-env-id-tail-correlation
kind: story
stage: done
tags: [documentation]
parent: null
depends_on: []
release_binding: app-v0.3.0
gate_origin: docs
created: 2026-07-25
updated: 2026-07-25
---

# DebugLog doc claims the app message id joins the relay's env_id_tail

## Location
`app/lib/domain/contracts/debug_log.dart:455-457`

## Contradiction
Sealed owner frames keep the app message id inside `outer.ct`; the relay
cannot join it. `env_id_tail` correlates cross-PC `pi_envelope` traffic
only (same contract as v0.3.0's gate-docs-agents-env-id-tail-sealed-frames).

## Implementation notes
Rewrote the cross-side correlation dartdoc: owner-message id joins
app↔extension tracing; env_id_tail is a separate cross-PC key.
Verification: flutter analyze clean.

## Review
Bounded inline review (orchestrator, 2026-07-25): matches the shipped
correlation contract. Approved -> done.
