---
id: feature-fleet-update-from-mobile-wire-protocol
kind: story
stage: implementing
tags: [pi-extension, app, protocol]
parent: feature-fleet-update-from-mobile
depends_on: []
release_binding: null
gate_origin: null
created: 2026-09-07
updated: 2026-09-07
---

# Wire protocol: fleet_update client message + fleet_update_status server events

Design element: Unit 1 of the feature body — read "Implementation Units /
Unit 1" for the message shapes, schema files, codegen output paths, and the
app-derived (not wire) restarting/verified phases.

## Acceptance evidence

- Codegen green; TS + Dart generated types committed; discriminator maps
  include both messages; `fleet_update` joins the session-scoped client
  list.
- Fixture rows: request + each status variant (updating / arming with peers
  / update_failed / already_running).
- Unknown-client-type error behavior covered by the existing codec test
  pattern (old extension + new app degrades cleanly).

## Ordering constraints

None — foundation story; extension-coordinator and app-ui depend on it.
