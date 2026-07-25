---
id: gate-tests-fakesession-buildcontext-duplicate-projection
created: 2026-07-24
updated: 2026-07-24
tags: [testing]
gate_origin: tests
---

# FakeSession.buildContext is a duplicate projection, not a boundary check

Priority: Low (parked per gate_finding_routing).
`pi-extension/src/extension/command_surface/pairing_coordinator.test.ts`'s
`FakeSession.buildContext()` maps the test-owned customMessages list, making
its model-context assertions a duplicate projection rather than an
independent SDK-boundary check. Remove it and its duplicate assertions once
`gate-tests-pairing-token-context-regression-representation-blind` (bound,
v0.3.0) lands the direct never-called assertion. Affinity: same file — fix
together with that item if convenient.
