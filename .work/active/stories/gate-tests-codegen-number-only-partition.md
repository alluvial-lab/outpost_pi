---
id: gate-tests-codegen-number-only-partition
kind: story
stage: implementing
tags: [testing, pi-extension]
parent: null
depends_on: []
release_binding: null
gate_origin: tests
created: 2026-07-24
updated: 2026-07-28
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
