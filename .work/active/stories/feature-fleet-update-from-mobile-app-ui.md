---
id: feature-fleet-update-from-mobile-app-ui
kind: story
stage: done
tags: [app, ux]
parent: feature-fleet-update-from-mobile
depends_on: [feature-fleet-update-from-mobile-wire-protocol]
release_binding: v0.12.0
gate_origin: null
created: 2026-09-07
updated: 2026-09-08
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

## Implementation notes

Implemented the settings Fleet section and its connection/room-derived update
state machine in `app/lib/ui/settings/fleet_update_viewmodel.dart` and
`app/lib/ui/settings/settings_page.dart`. The production send path is exposed
by `IActionsRepository.fleetUpdate()`, and the route plus embedded settings
sheet provide the ViewModel through the same DI shape as `SettingsViewModel`.

The first widget test failure was test-side, not a production defect. The
harness left `ConnectionManager`'s watchdog timer alive after the test; the
orphaned manager and its channel listeners then raced fake stream teardown.
The harness now releases ViewModel listeners before the manager and channel,
with an idempotent teardown registered for assertion-failure paths. The widget
harness also used `Future.delayed(Duration.zero)` under Flutter's FakeAsync;
that does not advance without a pump, so the PairOk delivery now uses the
explicit `WidgetTester.pump()` completion barrier. Assertions were unchanged.

A compatibility guard keeps `_FleetSection` absent when a directly embedded or
focused `SettingsPage` has no route-scoped fleet binding; normal routes and the
settings sheet provision `FleetUpdateViewModel` explicitly. This preserves the
existing SettingsPage construction contract while keeping production DI
explicit.

## Scope judgments and reviewer discovery

- DI/routing/settings_sheet edits were needed to provision
  `FleetUpdateViewModel`; they mirror `SettingsViewModel` exactly.
- Reconnect-banner suppression is ViewModel-complete and tested, but
  `chat_page`'s error-banner consumption of that flag was outside the prior
  write scope. This remains a discovery for the reviewer rather than an
  unrequested chat-surface change.
- Derivation pins the room id and session id at run start. If the watched room
  dies, `ConnectionManager.activeRoomId` may retarget; the run remains bound
  to its original room. `restarting` derives from room loss while the relay
  stays online as well as from transport drop. Verification requires that
  original room to be live again with a fresh, non-null session id. A wire
  event can resume a run that was derived as `restarting`, proving the event
  was a flap rather than a restart. *(Superseded by review fix 1 in c11b6652b:
  wrapper `--continue` preserves the SDK session id, so verification uses the
  room's new `startedAt` as the process-incarnation marker instead.)*

## Verification evidence

- `flutter analyze` — passed with no issues.
- `dart format` — passed on all touched app implementation and test files.
- `flutter test --timeout=40s --reporter=compact
  test/ui/settings/fleet_update_viewmodel_test.dart
  test/ui/settings/fleet_section_test.dart` — passed (22 ViewModel tests and
  5 widget tests).
- Full `flutter test --exclude-tags e2e --concurrency=2` was attempted. It
  ran 1,052 tests with one failure in the pre-existing protocol fixture
  classification test (`test/protocol_test.dart: decode fixtures server
  fixture lines parse through decodeServer`): the committed generated server
  registry contains `fleet_update_status`, while the local
  `.orchestration/contracts/fixtures` catalog has no corresponding fixture.
  The protocol story is already done and protocol files were outside this
  story's write scope, so that unrelated blocker is left for the reviewer.
