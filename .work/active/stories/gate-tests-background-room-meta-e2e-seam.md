---
id: gate-tests-background-room-meta-e2e-seam
kind: story
stage: done
tags: [testing, pi-extension, relay, app]
parent: null
depends_on: []
release_binding: v0.11.0
gate_origin: tests
created: 2026-08-28
updated: 2026-08-28
---

# Exercise background-work metadata through the real extension → relay → app seam

## Priority
High

## Value evidence
Item: `feature-background-work-working-state`

Contract / risk / regression / maintenance cost: the feature promises that
`subagents:*` lifecycle edges become `room_meta_update.background`, cross the
relay, update the app room snapshot, and ultimately drive the
`orchestrating…` status (`.work/active/features/feature-background-work-working-state.md:70-73,194-196,221-228`). Its integrated review already found a concrete seam failure: the first implementation bypassed the canonical schema, so the relay dropped `background` and the feature could not work end-to-end (`feature-background-work-working-state.md:353-358`).

Current tests stop at separately constructed boundaries: extension transition
frames (`pi-extension/src/extension.test.ts:7087-7101`), relay decode/merge/
broadcast (`relay/src/handlers/control.rs:567-586`), app parsing
(`app/test/transport/connection_manager_working_test.dart:111-150`), and widget
precedence (`app/test/ui/chat/background_status_test.dart:103-176`). Neither
`app/test/e2e/` nor `app/integration_test/` exercises `background` or
`orchestrating`. The known review blocker proves that component-local tests and
generated fixtures alone do not protect this exact cross-component contract.

## Gap type
e2e-seam / bug-regression

## Suggested test
```dart
test('background lifecycle crosses extension, relay, and app room metadata', () async {
  // Pair through PairingStack against the source-built relay and Pi SDK host.
  // Ask a narrow test-support endpoint to emit subagents:created on the real
  // pi.events bus. Assert the production ConnectionManager observes
  // RoomInfo.background == true for the paired room.
  // Emit subagents:completed and assert the same room converges false.
  // Do not inject room_meta_updated directly on the app side: the value must
  // originate in BackgroundActivityTracker and traverse the relay broadcast.
});
```

The Pi-host support endpoint should expose only lifecycle-event emission needed
by this test (created/terminal id), not a shortcut that writes room metadata.

## Test location (suggested)
`app/test/e2e/background_work_metadata_e2e_test.dart`, with narrow support in
`pi-extension/test/support/e2e_pi_host_{server,runtime}.ts` and
`app/test/e2e/support/pi_host_client.dart`

## Implementation notes

- Added `app/test/e2e/background_room_meta_e2e_test.dart` to the existing
  headless `e2e/run-pairing.sh` battery. The lane pairs through `PairingStack`,
  listens to the real app `IControlLink`, and asserts the production
  `RoomMetaUpdated.background` frames and `ConnectionManager` room snapshot.
- Added a narrow test-only `/background-control` Pi-host endpoint and app
  client helper. It emits only allowlisted `subagents:created`,
  `subagents:completed`, `subagents:failed`, or `subagents:resumed` events on
  the real SDK event bus; it cannot write room metadata directly.
- The test covers duplicate and overlapping active ids, partial terminal drain,
  and completed/resumed/failed terminal edges. Expected transition values are
  `[true, false, true, false]`, proving the field survives extension → relay
  decode/merge/broadcast → app decode/snapshot.
- Verification: `e2e/run-pairing.sh` passed with `18` tests, including the new
  lane; the new lane logged four `room_meta_updated` control frames.
  `flutter analyze` passed with no issues.
