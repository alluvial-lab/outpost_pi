# Pattern: E2E Selector-to-Harness Scenarios

## Rationale

The live E2E program separates environment ownership from scenario ownership. The shell runner maps a small selector to a checked-in integration test, adds the required compose lane, and runs explicit phases when a file needs process restarts. Each scenario then owns its `LiveDeviceHarness` lifecycle, pairing state, fault requests, assertions, and teardown. This keeps CI entry points reproducible while allowing the same harness to express golden, failure, grid, mesh, and delivery journeys.

## When to use

Use when adding a live-device scenario:

1. Add a stable selector or an explicit `integration_test/*.dart` path in the runner.
2. Select any extra compose lane from the runner, not from test-specific environment guessing.
3. Let the Dart scenario create/restore the harness, perform the user journey, assert observable invariants, and close the harness in `finally`.
4. Use runner phases only where a force-stop or fresh process is part of the contract.

## When not to use

Do not put Docker, emulator, ADB, or process cleanup logic in every Dart scenario. Do not bypass selector validation with arbitrary filesystem paths, and do not make a scenario depend on another test's in-memory state without an explicit restore/phase contract.

## Examples

### Example 1: Validate selectors and choose the environment lane

**File:** `e2e/run-live.sh:14-29`

```bash
TEST_SELECTOR="${1:-${E2E_LIVE_TEST_FILE:-integration_test/live_infra_smoke_test.dart}}"
MESH_LANE=0
case "$TEST_SELECTOR" in
  state-shapes) TEST_FILE=integration_test/live_state_shapes_test.dart ;;
  grid) TEST_FILE=integration_test/live_grid_test.dart ;;
  mesh) TEST_FILE=integration_test/live_mesh_test.dart; MESH_LANE=1 ;;
  capture-delivery) TEST_FILE=integration_test/live_capture_delivery_test.dart ;;
  *) TEST_FILE="$TEST_SELECTOR" ;;
esac
# Validate the resulting path before running Flutter.
case "$TEST_FILE" in integration_test/*.dart) ;; *) exit 2 ;; esac
```

The runner owns selector translation, mesh compose selection, and path containment.

### Example 2: Run explicit fresh-process phases

**File:** `e2e/run-live.sh:381-394`

```bash
if [[ "$TEST_FILE" == integration_test/live_golden_test.dart ]]; then
  run_device_test pair-chat
  "$ADB_BIN" -s "$ANDROID_SERIAL" shell am force-stop dev.kevoun.outpostpi
  run_device_test cold-open
  "$ADB_BIN" -s "$ANDROID_SERIAL" shell am force-stop dev.kevoun.outpostpi
  run_device_test reconnect
elif [[ "$TEST_FILE" == integration_test/live_failure_test.dart ]]; then
  run_device_test failure-main
  "$ADB_BIN" -s "$ANDROID_SERIAL" shell am force-stop dev.kevoun.outpostpi
  run_device_test blank-cold
fi
```

The process boundary is visible in the runner instead of hidden in a test's timing assumptions.

### Example 3: Keep a failure journey self-contained in the harness

**File:** `app/integration_test/live_failure_test.dart:29-50`

```dart
final harness = await LiveDeviceHarness.create(restorePair: false);
try {
  await harness.pair(tester);
  await harness.mountChat(tester);
  requestLiveFault('net_fault down');
  await eventually<bool>(
    tester,
    () async => harness.connection.status is! StatusOnline ? true : null,
    description: 'forced reconnect edge',
  );
  requestLiveFault('net_clear');
  await eventually<bool>(
    tester,
    () async => harness.connection.status is StatusOnline ? true : null,
    description: 'relay reconnect before fresh room hydration',
  );
  await harness.sync.sendMessage(_swallowPrompt);
  await harness.waitForSubmissionVisibility(tester, _swallowPrompt);
} finally {
  await harness.close(tester);
}
```

### Example 4: Reuse the same shape for a golden scenario

**File:** `app/integration_test/live_golden_test.dart:22-46`

```dart
final harness = await LiveDeviceHarness.create(restorePair: false);
try {
  await harness.pair(tester);
  await harness.mountChat(tester);
  await harness.sendAndResolve(
    tester,
    prompt: _firstPrompt,
    reply: _firstReply,
  );
  expect(find.text(_firstPrompt), findsOneWidget);
  expect(find.text(_firstReply), findsOneWidget);
} finally {
  await harness.close(tester);
}
```

### Example 5: Extend the harness for a mesh topology

**File:** `app/integration_test/live_mesh_test.dart:24-57`

```dart
final harness = await LiveDeviceHarness.create(
  restorePair: false,
  enableMesh: true,
);
try {
  final piA = await harness.pair(tester);
  final piB = await harness.pairSecondary(tester);
  expect(piA.remoteEpk, isNot(piB.remoteEpk));
  await harness.publishMeshMembership();
  final topology = await _waitForMeshTopology(
    tester,
    harness,
    piB.remoteEpk,
  );
  await harness.mountChat(tester);
  await _verifyCrossPiDeviceVisibility(tester, harness, topology);
} finally {
  await harness.close(tester);
}
```

## Common violations

- Duplicating emulator, compose, or ADB cleanup in a scenario body.
- Letting one scenario's persisted state be an undocumented prerequisite for another.
- Adding a selector without a checked-in test file or without the runner's path guard.
- Omitting `finally` teardown after a faulted or paired run.
