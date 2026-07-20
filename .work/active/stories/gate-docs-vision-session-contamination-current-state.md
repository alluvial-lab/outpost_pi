---
id: gate-docs-vision-session-contamination-current-state
kind: story
stage: implementing
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.2.0
gate_origin: docs
created: 2026-07-20
updated: 2026-07-20
---

# Vision anti-vision says chat messages lack a session discriminator

## Drift category
foundation-doc-assertion

## Location
- Doc: `docs/VISION.md:86-89`
- Contradicting source: `docs/DECISIONS.md:81`

## Current doc text
> The system has no session discriminator on chat-bearing messages and relies on relay-room demux that fails open.

## Contradiction
The canonical `session_id` was restored on session-scoped traffic and the app rejects missing or foreign values before mutation. The described failure mode is no longer current truth.

## Required edit
Rewrite the anti-vision entry to state the current session-isolation failure mode or remove the resolved failure mode. Do not retain a historical-state assertion.

## Audit
Documentation drift audit ran inline because nested scanner dispatch was prohibited; isolation was reduced.
