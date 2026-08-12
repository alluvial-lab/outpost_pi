---
id: gate-tests-codegen-number-only-partition
kind: story
stage: done
tags: [testing, pi-extension]
parent: null
depends_on: []
release_binding: v0.4.0
gate_origin: tests
created: 2026-07-24
updated: 2026-08-11
---

# Codegen conditional-helper tests miss the number-only partition

Priority: Medium (parked per gate_finding_routing).
`gate-cruft-generated-validator-unused-number-helper` requires helpers to be
emitted only when referenced. Tests cover no-number and minimum-number
schemas, but omit: a plain `type: "number"` field (no minimum) needs
`isFiniteNumber` while NOT needing `isFiniteNumberAtLeast`. Generate such a
schema, assert base present / at-least absent, and prove the generated
validator accepts finite values and rejects NaN/infinities. Location:
`tools/protocol-codegen/src/index.test-cases.ts`.

## Implementation notes

- Changed `tools/protocol-codegen/src/index.test-cases.ts`.
- Added a plain `type: "number"` schema partition test that asserts
  `isFiniteNumber` is emitted while `isFiniteNumberAtLeast` is absent.
- The generated client validator accepts finite values and rejects `NaN`,
  positive infinity, and negative infinity.
- Verification: `NODE_PATH=/home/agent/projects/outpost_pi/pi-extension/node_modules CI=true
  /home/agent/projects/outpost_pi/pi-extension/node_modules/.bin/vitest run
  --root tools/protocol-codegen` passed with 7 tests; the package-local command
  was unavailable because `tools/protocol-codegen` has no installed
  `node_modules`.
