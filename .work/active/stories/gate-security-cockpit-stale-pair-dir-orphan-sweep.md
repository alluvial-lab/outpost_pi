---
id: gate-security-cockpit-stale-pair-dir-orphan-sweep
kind: story
stage: implementing
tags: [security, cockpit]
parent: null
depends_on: []
release_binding: null
gate_origin: security
created: 2026-07-27
updated: 2026-07-28
---

# Cockpit crash orphans the token-bearing pair seam directory

Severity: Low (parked per gate_finding_routing).
A Cockpit crash bypasses pairing-gateway cleanup entirely, leaving an
`outpost-pi-pair-*` private temp directory containing a still-valid bearer
token until expiry/manual deletion. (The boot-timeout-doesn't-clean-up half
of this finding is covered by the bound
`gate-refactor-pairing-gateway-finalizer-leaks`.) Fix direction: a narrowly
scoped stale-pair-directory recovery sweep at Cockpit startup — owner-only
validation, no broad temp deletion; seed-test with an abandoned seam dir.
