---
id: feature-fleet-update-from-mobile-wire-protocol
kind: story
stage: done
tags: [pi-extension, app, protocol]
parent: feature-fleet-update-from-mobile
depends_on: []
release_binding: v0.12.0
gate_origin: null
created: 2026-09-07
updated: 2026-09-07
---

# Wire protocol: fleet_update client message + fleet_update_status server events

Design element: Unit 1 of the feature body — read "Implementation Units /
Unit 1" for the message shapes, schema files, codegen output paths, and the
app-derived (not wire) restarting/verified phases.

## Acceptance evidence

- [x] Codegen green; TS + Dart generated types committed; discriminator maps
  include both messages; `fleet_update` joins the session-scoped client
  list.
- [x] Fixture rows: request + each status variant (updating / arming with peers
  / update_failed / already_running).
- [x] Unknown-client-type error behavior covered by the existing codec test
  pattern (old extension + new app degrades cleanly).

## Completion evidence

- Protocol schema fixtures and generated TypeScript/Dart outputs are updated.
- Protocol, codegen, extension codec/session-scope, and app generated-codec
  unit tests pass.
- No live Pi process or relay was operated.

## Ordering constraints

None — foundation story; extension-coordinator and app-ui depend on it.
