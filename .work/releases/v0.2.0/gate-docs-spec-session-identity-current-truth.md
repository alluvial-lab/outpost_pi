---
id: gate-docs-spec-session-identity-current-truth
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

# SPEC describes restored session identity as an open future question

## Drift category
foundation-doc-assertion

## Location
- Doc: `docs/SPEC.md:142-149`
- Contradicting source: `docs/DECISIONS.md:81`

## Current doc text
> The wire carries no `session_id` on chat-bearing messages today ... [and] treats the canonical-session direction as in-flight.

## Contradiction
The decisions registry records the restored canonical `session_id` as current truth: it is required on session-scoped pushes and rejected fail-closed by the app. The specification's open-question framing is therefore false current-state documentation.

## Required edit
Replace the obsolete open-question entry with the current canonical-session invariant, or remove it from the resolved-questions list. Keep the active truth in place without historical-release prose.

## Audit
Documentation drift audit ran inline because nested scanner dispatch was prohibited; isolation was reduced.

## Implementation notes
- **Execution:** Bounded inline documentation repair; the source-of-truth transport contract and app session gate made the correction deterministic.
- **Change:** Removed the obsolete open question claiming chat traffic lacks `session_id`; `docs/SPEC.md` now relies on its current canonical, required, fail-closed session invariant.
- **Verification:** Confirmed the stale assertion is absent and the existing transport section matches `docs/DECISIONS.md` plus `app/lib/data/sync/session_gate.dart`. No automated test applies to this prose-only correction.
- **Bounded inline review:** Pass — the edit removes historical drift without changing adjacent specification content.
