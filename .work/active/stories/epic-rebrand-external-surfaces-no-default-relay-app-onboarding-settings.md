---
id: epic-rebrand-external-surfaces-no-default-relay-app-onboarding-settings
kind: story
stage: done
tags: [rebrand, app]
parent: epic-rebrand-external-surfaces-no-default-relay
depends_on: [epic-rebrand-external-surfaces-no-default-relay-app-resolution-handling]
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-15
---

# Require a self-hosted relay in onboarding and settings

## Scope

Apply the settled no-default relay contract to the mobile configuration UI.
Remove the community choice rather than leaving a disabled legacy option. Make
an empty input fail visibly and make existing unconfigured installations visible
and recoverable from Settings.

## Acceptance criteria

- [x] `RelayChoice.community`, its UI callback, and the Community relay card are
  removed; the relay step is a single self-hosted URL form.
- [x] The form cannot continue with empty or invalid input; submit shows the
  shared validation error and a valid URL is persisted before pairing.
- [x] Settings starts with an empty field for no stored URL, labels the current
  state as not configured, removes the "Use default Relay" button, and retains
  validation plus reconnect-after-save behavior.
- [x] Onboarding and settings ViewModel/widget tests prove that no community
  fallback/card remains and that an unconfigured state is actionable.
- [x] `flutter analyze` and focused Flutter tests pass.

## Implementation notes

- Removed the relay-choice state and callback. The relay step is now a single
  self-hosted URL field with a lifecycle-owned `TextEditingController`.
- The Continue button intentionally remains enabled for an empty value: its
  ViewModel submission renders the shared URL validation error instead of
  silently disabling the only recovery action. `next()` awaits preference
  persistence before moving to pairing, so pairing cannot observe an
  unconfigured relay.
- Settings uses the canonical `RelayResolution` supplied by the dependency.
  Empty submissions now return the same shared URL validation message rather
  than the obsolete default-relay instruction; successful saves retain the
  disconnect-and-boot reconnect path.
- Added onboarding ViewModel/widget coverage for the missing community path,
  required empty validation, and persisted valid URLs; added Settings
  ViewModel/widget coverage for actionable unconfigured state and reconnect.

## Verification

- `PUB_CACHE=/home/agent/projects/remote_pi/.pub-cache /home/agent/projects/remote_pi/.tools/flutter/bin/flutter test test/ui/onboarding/onboarding_viewmodel_test.dart test/ui/onboarding/relay_step_test.dart test/ui/settings/settings_viewmodel_test.dart test/ui/settings/settings_page_test.dart`
- `PUB_CACHE=/home/agent/projects/remote_pi/.pub-cache /home/agent/projects/remote_pi/.tools/flutter/bin/flutter analyze`
