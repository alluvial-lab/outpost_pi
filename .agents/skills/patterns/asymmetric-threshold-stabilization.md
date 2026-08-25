# Pattern: Asymmetric Threshold Stabilization

## Rationale

Noisy measurements and animated transitions should not flip a semantic state at every sample. Use a stricter entry condition and a separate exit condition, or require several consecutive healthy observations before declaring recovery. The margin or run length is intentional hysteresis: transient keyboard frames, missed pings, and briefly restored services do not cause visible or operational flapping.

## When to use

Use when a state is derived from a changing measurement and both directions have different confidence requirements:

- name the entry and exit thresholds in the owning policy;
- reset a healthy-observation counter on any failed probe;
- test values around both boundaries and the stable-recovery requirement.

## When not to use

Do not add hysteresis to exact protocol validation, monotonic sequence admission, or a one-shot user action where every edge is meaningful. Do not use a margin to conceal an unbounded retry or lifecycle leak.

## Examples

### Example 1: Composer compact mode has separate entry and exit bounds

**File:** `app/lib/ui/chat/chat_page.dart:131-143`

```dart
if (compact == null) {
  return _compactComposer =
      availableHeight < kCompactComposerAvailableHeight;
}
if (compact) {
  if (availableHeight > kCompactComposerExitHeight) {
    _compactComposer = false;
  }
} else if (availableHeight < kCompactComposerAvailableHeight) {
  _compactComposer = true;
}
return _compactComposer!;
```

The composer enters below 280dp but does not restore standard chrome until height exceeds 360dp.

### Example 2: Reachability degrades after misses and recovers on real inbound traffic

**File:** `app/lib/data/transport/reachability_adapter.dart:50-60` and `app/lib/domain/value_objects/reachability.dart:44-61`

```dart
void onAppFrameObserved() {
  _state = ReachabilityState.online;
  _retryAttempt = 0;
  _missedPings = 0;
}

void onPingMissed() {
  _missedPings += 1;
  if (_missedPings >= reachabilityHeartbeat.degradedAfterMissedAppPongs) {
    _state = ReachabilityState.degraded;
  }
}
```

The policy names three missed app pongs as the degradation threshold; one real inbound frame is the stronger recovery signal and resets the streak.

### Example 3: The live runner requires consecutive healthy probes before reconnecting

**File:** `app/integration_test/live_infra_smoke_test.dart:218-228`

```dart
var consecutiveHealthyProbes = 0;
await _eventually<bool>(tester, () async {
  if (await _relayHealthReachable(
    timeout: const Duration(milliseconds: 150),
  )) {
    consecutiveHealthyProbes++;
  } else {
    consecutiveHealthyProbes = 0;
  }
  return consecutiveHealthyProbes >= 5 ? true : null;
}, description: 'stable app-relay proxy restoration');
```

A single restored probe is not treated as a recovered relay; five consecutive successes are required, and one failure returns the counter to zero.

### Example 4: The regression test exercises the noisy keyboard ramp

**File:** `app/test/ui/chat/chat_compact_composer_test.dart:185-214`

```dart
for (final inset in <double>[130, 145, 135, 160, 280]) {
  tester.view.viewInsets = FakeViewPadding(bottom: inset);
  await tester.pump();
  observedMaxLines.add(maxLines());
}

expect(
  observedMaxLines,
  <int>[6, 6, 1, 1, 1, 1],
  reason: 'threshold jitter during the IME ramp must not bounce the composer',
);
```

The test makes the stabilization contract executable instead of only testing the final settled inset.

## Common violations

- Reusing one threshold for both entry and exit when the input is noisy.
- Incrementing a healthy counter without resetting it after a failed probe.
- Treating one reconnect success as proof that the whole dependency chain is live.
- Testing only the settled value and never exercising the boundary jitter.
