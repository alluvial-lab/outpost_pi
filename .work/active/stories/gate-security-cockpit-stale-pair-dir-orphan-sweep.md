---
id: gate-security-cockpit-stale-pair-dir-orphan-sweep
kind: story
stage: review
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

## Implementation notes

- Added `PairingSeamCleanup` and invoked its exact-prefix, owner-only sweep during Cockpit startup before new pairing sessions can be created.
- Added `cockpit/test/core/data/relay/pairing_seam_cleanup_test.dart`, seeding a private abandoned seam with a bearer-token file and preserving an unrelated directory.
- Verification: targeted sweep test passes; full `flutter analyze` and `flutter test` run after the remaining docs story.
- Parked issue: none.
