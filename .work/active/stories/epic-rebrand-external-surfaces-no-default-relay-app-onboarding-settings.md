---
id: epic-rebrand-external-surfaces-no-default-relay-app-onboarding-settings
kind: story
stage: implementing
tags: [rebrand, app]
parent: epic-rebrand-external-surfaces-no-default-relay
depends_on: [epic-rebrand-external-surfaces-no-default-relay-app-resolution-handling]
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
---

# Require a self-hosted relay in onboarding and settings

## Scope

Apply the settled no-default relay contract to the mobile configuration UI.
Remove the community choice rather than leaving a disabled legacy option. Make
an empty input fail visibly and make existing unconfigured installations visible
and recoverable from Settings.

## Acceptance criteria

- [ ] `RelayChoice.community`, its UI callback, and the Community relay card are
  removed; the relay step is a single self-hosted URL form.
- [ ] The form cannot continue with empty or invalid input; submit shows the
  shared validation error and a valid URL is persisted before pairing.
- [ ] Settings starts with an empty field for no stored URL, labels the current
  state as not configured, removes the "Use default Relay" button, and retains
  validation plus reconnect-after-save behavior.
- [ ] Onboarding and settings ViewModel/widget tests prove that no community
  fallback/card remains and that an unconfigured state is actionable.
- [ ] `flutter analyze` and focused Flutter tests pass.
