---
id: epic-rebrand-external-surfaces-no-default-relay-app-resolution-handling
kind: story
stage: done
tags: [rebrand, app]
parent: epic-rebrand-external-surfaces-no-default-relay
depends_on: []
release_binding: v0.1.0
gate_origin: null
created: 2026-07-14
updated: 2026-07-15
---

# Make the app transport stack handle an unconfigured relay

## Scope

Replace the app's string fallback with the parent feature's sealed
`RelayResolution` state and handle the unconfigured branch at every transport
boundary. Preserve the stored relay URL format and normal URL validation; this
story does not redesign onboarding/settings presentation.

## Acceptance criteria

- [x] `app/lib/data/transport/relay_config.dart` has no community default and
  resolves either `ConfiguredRelay(url)` or `UnconfiguredRelay`.
- [x] Pairing refuses an unconfigured relay before it opens a transport, with an
  actionable non-retryable error; `pair_request_flow.dart` retains only its
  explicit-string pairing contract and drops its resolver compatibility shim.
- [x] The production connection factory converts the unconfigured state into a
  typed configuration failure; `ConnectionManager` exposes `StatusOffline`
  with `canRetry: false` and does not let the watchdog create a retry loop.
- [x] `MeshClient` returns its existing typed fetch/publish failure results for
  an unconfigured resolution without constructing an invalid URI or issuing
  HTTP; DI supplies the resolution rather than a nullable string.
- [x] Legacy installed state (a completed onboarding flag with no stored relay)
  remains representable and reaches the above actionable failures rather than
  silently reconnecting to a retired host.
- [x] Resolver, pairing, connection-manager, and mesh-client tests cover the
  unconfigured branch; configured URL behavior remains covered.
- [x] `flutter analyze` and focused Flutter tests pass.

## Implementation notes

- `RelayResolution` is the sole relay-presence decision. Production DI and both
  WebSocket factories narrow `ConfiguredRelay` before any identity or transport
  work; the named exception distinguishes absent configuration from retryable
  network failure.
- `ConnectionManager` clears in-flight reachability and checks
  `StatusOffline.canRetry` in its watchdog before emitting the non-retryable
  configuration state. The watchdog test invokes its extracted tick directly
  rather than waiting on a real timer.
- `MeshClient` accepts the typed resolver from production DI and checks it
  before URI construction. Its deprecated string-provider constructor remains
  only as a test seam for pre-existing mesh-sync fixtures; production has no
  string resolver path.
- Removing the obsolete default constant required deleting Settings' default
  action and its direct use in the onboarding card. The onboarding story still
  owns the remaining card/mandatory-form redesign; these minimal changes only
  prevent a retired fallback from being referenced.

## Verification

- `PUB_CACHE=/home/agent/projects/remote_pi/.pub-cache /home/agent/projects/remote_pi/.tools/flutter/bin/flutter analyze`
- Focused `flutter test` suites: relay config, connection manager, mesh client,
  pairing ViewModel, Settings ViewModel, and mesh sync service — all passed.
