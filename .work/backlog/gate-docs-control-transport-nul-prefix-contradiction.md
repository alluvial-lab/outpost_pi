---
id: gate-docs-control-transport-nul-prefix-contradiction
created: 2026-07-19
updated: 2026-07-19
tags: [docs, cockpit, pi-extension]
---

# Foundation docs contradict the tested control transport (NUL-prefix vs structured JSON)

## Source

Parked from the `standard`-weight cross-model review of
`feature-cockpit-settings-control-tests` (2026-07-19). Lower-risk finding —
docs drift, predates the feature.

## Finding

`docs/SPEC.md` (lines ~69-70, 88-89) and `docs/ARCHITECTURE.md` (lines ~24,
116-117, 181-184) simultaneously state that the NUL-prefix control protocol
was retired AND describe it as Cockpit's active transport. Cockpit now emits
structured `outpost_pi_control` JSON (the 0.1.0 rebrand cutover); the
NUL-prefix is extension-side compatibility only, not the active transport.

This is a foundation-doc contradiction (false/stale assertion), not a test
defect — the feature's tests correctly exercise the structured-JSON transport.

## Risk rationale (why parked, not fixed this cycle)

Predates the test feature; does not invalidate its tests. The risk is that a
future agent reads the stale "active transport = NUL-prefix" assertion and
restores an incompatible legacy encoding. Belongs to the `gate-docs` release
gate's drift detection, not the test feature's scope.

## Recommended direction

Reconcile the control-transport description in `docs/SPEC.md` and
`docs/ARCHITECTURE.md`: state that Cockpit emits structured
`outpost_pi_control` JSON as the active transport, and that the NUL-prefix
(`\x00outpost-pi-ctrl:`) is extension-side compatibility handling, not a
Cockpit-emitted form. Cross-reference the 0.1.0 rebrand cutover note in
`AGENTS.md` ("Cockpit control-RPC discriminator ... hard cutover").
