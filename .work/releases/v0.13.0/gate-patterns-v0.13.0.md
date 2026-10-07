---
id: gate-patterns-v0.13.0
kind: story
stage: done
tags: [docs, workflow]
parent: null
depends_on: []
release_binding: v0.13.0
gate_origin: patterns
created: 2026-10-05
updated: 2026-10-05
---

# gate-patterns v0.13.0: diagnostic-schema-and-emission-coverage

One pattern met the bar (3 verified occurrences: ConnCancelEvent — bundle
addition — plus existing LifecycleFailureEvent and WsInEvent families, each
with schema/registry + production-seam routing structure):
`diagnostic-schema-and-emission-coverage` written to
`.agents/skills/patterns/`, digest regenerated.

Rejected candidates (below the 3-occurrence bar or already covered):
injected dependency seams (injected-effect-coordinators exists),
drop-oldest bounded queues (single complete implementation), edge-triggered
notification gating (edge-triggered-convergence exists), deterministic
factory-start barriers (two existing patterns cover it), two-guard CLI
invariant framing (single implementation; docs/tests repeat its contract).
