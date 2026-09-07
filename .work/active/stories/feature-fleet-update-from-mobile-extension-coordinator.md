---
id: feature-fleet-update-from-mobile-extension-coordinator
kind: story
stage: implementing
tags: [pi-extension]
parent: feature-fleet-update-from-mobile
depends_on: [feature-fleet-update-from-mobile-wire-protocol]
release_binding: null
gate_origin: null
created: 2026-09-07
updated: 2026-09-07
---

# Extension: fleet coordinator (update subprocess + self-arm + mesh broadcast) + sibling arm handler

Design element: Unit 2 of the feature body — read "Implementation Units /
Unit 2" for the FleetUpdateCoordinator signature, the phase-emission
ordering rule (status before any arm; self-arm LAST), the sibling
arm-restart mesh message + ack states, and the safety rails (existing
.hot-reload-enabled toggle, own-nonce armed files, settle-gated claims).

## Acceptance evidence

- Unit tests (injected fakes): success path phase order; update failure →
  no arm; concurrent request → already_running; ack table incl.
  declined/deferred/no-ack rows; report-before-self-arm ordering.
- Sibling handler tests: arms when enabled (own-nonce file, fs-mocked);
  declines with reason when the host toggle is off or disposed.
- Live lane on one VM: harness trigger → wrapper bounce observed on all pis
  (the wrapper restart path is the already-verified 2.3s-bounce rail).
- `corepack pnpm typecheck && test && build` green.

## Ordering constraints

Depends on the wire-protocol story. Live lane requires one pi restart to
load the new dist (ESM) — the bootstrap note in the feature's Risks.
