---
id: feature-fleet-update-from-mobile-app-ui
kind: story
stage: implementing
tags: [app, ux]
parent: feature-fleet-update-from-mobile
depends_on: [feature-fleet-update-from-mobile-wire-protocol]
release_binding: null
gate_origin: null
created: 2026-09-07
updated: 2026-09-07
---

# App: Fleet settings section + update state machine with reconnect suppression

Design element: Unit 3 of the feature body — read "Implementation Units /
Unit 3" for the FleetUpdateState machine, the derivation rules for
restarting/verified/lost (the coordinator cannot report its own exit), the
reconnect-error-banner suppression scope, and the confirmation-gated
button behavior.

## Acceptance evidence

- Viewmodel tests: wire-event → state mapping; transport drop during a run
  → restarting WITHOUT the error banner; room re-announce → verified; no
  recovery within timeout → FleetUpdateLost and normal error UX resumes;
  every terminal path clears the suppression flag (scan-lifecycle class).
- Widget tests: confirmation gate before send; disabled-with-reason when
  no owned room connected; phase + per-pi ack list rendering.
- `flutter analyze && flutter test --exclude-tags e2e` green.
- Optional-if-heavy (implementation judgment): pairing-suite lane covering
  trigger → status → update_failed.

## Ordering constraints

Depends on the wire-protocol story only — testable against fixture status
events before any extension publishes them.
