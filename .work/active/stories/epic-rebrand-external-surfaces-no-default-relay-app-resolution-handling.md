---
id: epic-rebrand-external-surfaces-no-default-relay-app-resolution-handling
kind: story
stage: implementing
tags: [rebrand, app]
parent: epic-rebrand-external-surfaces-no-default-relay
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
---

# Make the app transport stack handle an unconfigured relay

## Scope

Replace the app's string fallback with the parent feature's sealed
`RelayResolution` state and handle the unconfigured branch at every transport
boundary. Preserve the stored relay URL format and normal URL validation; this
story does not redesign onboarding/settings presentation.

## Acceptance criteria

- [ ] `app/lib/data/transport/relay_config.dart` has no community default and
  resolves either `ConfiguredRelay(url)` or `UnconfiguredRelay`.
- [ ] Pairing refuses an unconfigured relay before it opens a transport, with an
  actionable non-retryable error; `pair_request_flow.dart` retains only its
  explicit-string pairing contract and drops its resolver compatibility shim.
- [ ] The production connection factory converts the unconfigured state into a
  typed configuration failure; `ConnectionManager` exposes `StatusOffline`
  with `canRetry: false` and does not let the watchdog create a retry loop.
- [ ] `MeshClient` returns its existing typed fetch/publish failure results for
  an unconfigured resolution without constructing an invalid URI or issuing
  HTTP; DI supplies the resolution rather than a nullable string.
- [ ] Legacy installed state (a completed onboarding flag with no stored relay)
  remains representable and reaches the above actionable failures rather than
  silently reconnecting to a retired host.
- [ ] Resolver, pairing, connection-manager, and mesh-client tests cover the
  unconfigured branch; configured URL behavior remains covered.
- [ ] `flutter analyze` and focused Flutter tests pass.
