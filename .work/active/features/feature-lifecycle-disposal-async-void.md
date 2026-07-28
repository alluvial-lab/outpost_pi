---
id: feature-lifecycle-disposal-async-void
kind: feature
stage: drafting
tags: [pi-extension, app, lifecycle]
parent: null
depends_on: []
release_binding: null
gate_origin: refactor
created: 2026-07-28
updated: 2026-07-28
---

# Lifecycle disposal + unguarded-async-void convergence

## Brief
Five `gate-refactor` findings (scan library `lifecycle`, rules
`resource-no-dispose` and `unguarded-async-void`) identify resources and async
teardown paths that escape owned lifecycle boundaries across the extension and
app. This is the repo's highest-risk defect class (per
`.agents/rules/testing-integrity.md` — async and lifecycle). Two rules:

`resource-no-dispose` — a registered resource (stream subscription, WebSocket
listener, watcher) has no disposal hook on its owning lifecycle boundary:
- `gate-refactor-lifecycle-owner-identity-watcher-no-dispose` —
  `app/lib/config/dependencies.dart:96` `OwnerIdentityBridge` owns a platform
  stream subscription with `dispose()` but `addInstance` provides no disposal
  hook, so `disposeDependencies()` never cancels it.
- `gate-refactor-lifecycle-relay-auth-timeout-listener` —
  `pi-extension/src/transport/relay_client.ts:253` auth timeout rejects without
  removing the `ws.once("message")` listener, leaving a stale listener.

`unguarded-async-void` — an async teardown is fire-and-forget, racing shutdown
or dropping rejections:
- `gate-refactor-lifecycle-bye-frames-race-relay-shutdown` —
  `pi-extension/src/index.ts:943` `_goIdle` enqueues protected bye frames,
  detaches channels, and closes the relay without awaiting each secure
  channel's persistence/send drain.
- `gate-refactor-lifecycle-owner-ingress-floating` —
  `pi-extension/src/index.ts:319` the relay outer-message callback voids
  `_handleOwnerOuterFrame(...)` without awaiting or attaching a rejection
  handler.
- `gate-refactor-lifecycle-self-revoke-discards-async-detach` —
  `pi-extension/src/extension/command_surface/pairing_coordinator.ts:213`
  `onRevoke` discards the `Promise` from `owners.detach` though `SelfRevoke`
  supports and awaits async callbacks.

## Simplification opportunity
A single owned-async-teardown boundary (named cleanup shared by timeout/success
paths; an awaited `whenIdle` before relay close; a rejection observer on
floating ingress) removes five independent leaks and the unhandled-promise-
rejection class they invite. Coordinate with the already-advanced
`gate-patterns-inconsistency-pairing-coordinator-stale-capability` story (same
stale-capability-across-replacement class, same `pairing_coordinator.ts` file).

## Design notes
Scan library `scan-lifecycle` declares `findings-route: none` (fixes are not
black-box-preserving — they change teardown ordering/await behavior), so this
routes through `feature-design`, not `refactor-design`. The design pass should
sequence: the bye-frames race and the auth-timeout listener are the highest-
risk (shutdown ordering / stale WebSocket listener); the floating ingress and
self-revoke async-detach are unhandled-rejection sources; the app identity-
watcher is a pure disposal-binding fix. Verify each with the lifecycle/async
tests (`scan-lifecycle` rule library + existing turn-state/projection suites).
