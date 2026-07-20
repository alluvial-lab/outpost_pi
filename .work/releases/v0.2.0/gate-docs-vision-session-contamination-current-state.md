---
id: gate-docs-vision-session-contamination-current-state
kind: story
stage: done
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

## Implementation notes
- **Execution:** Bounded inline documentation repair; current generated protocol and app boundary code directly establish the invariant.
- **Change:** Replaced the claim that chat has no session discriminator with the current failure mode: bypassing required `session_id` stamping or the app's fail-closed gate would violate isolation.
- **Verification:** Confirmed the obsolete assertion is absent and the replacement matches `docs/DECISIONS.md` and `app/lib/data/sync/session_gate.dart`. No automated test applies to this prose-only correction.
- **Bounded inline review:** Pass — the anti-vision remains a failure-mode statement while describing current safeguards.
