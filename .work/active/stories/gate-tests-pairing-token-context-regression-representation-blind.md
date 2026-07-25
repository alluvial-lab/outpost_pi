---
id: gate-tests-pairing-token-context-regression-representation-blind
kind: story
stage: review
tags: [testing]
parent: null
depends_on: []
release_binding: v0.3.0
gate_origin: tests
created: 2026-07-24
updated: 2026-07-24
---

# Pairing-token context regression test is representation-blind

## Priority
High

## Value evidence
Item: `gate-security-pairing-token-in-model-context`. The contract is that
pairing material never enters Pi custom messages or model context. The new
test (`pi-extension/src/extension/command_surface/pairing_coordinator.test.ts`)
rejects only literal URI/token text, so a regression that sends only the QR
ASCII — which still encodes the bearer token — would pass.

## Gap type
test-integrity

## Suggested test
Assert `sendPiMessage` was never called and `session.customMessages` is empty
after TUI rendering, regardless of representation. This directly fails any
return to the SDK message path. (See parked
`gate-tests-fakesession-buildcontext-duplicate-projection`: once this direct
assertion exists, the hand-built context projection can go.)

## Test location (suggested)
`pi-extension/src/extension/command_surface/pairing_coordinator.test.ts`

## Implementation notes
- Replaced representation-dependent URI/token substring checks with a direct `sendPiMessage` never-called assertion after TUI rendering and an empty custom-message sink assertion.
- Removed `FakeSession.buildContext()` and its duplicate test-owned model-context projection.
- Verification: `cd pi-extension && ./node_modules/.bin/vitest run src/extension/command_surface/pairing_coordinator.test.ts` (2 passed).
