# Pattern: Failure-First Regression Tests

## Rationale

A regression test should make the defect's boundary visible before asserting the repaired behavior. Start with the exact setup that used to fail, assert the intermediate failure-sensitive state, trigger the competing event or lifecycle transition, and then assert the invariant that must survive. This makes the test fail against the pre-fix implementation instead of merely restating the final happy path.

When the defect is an async race, combine this shape with `explicit-async-interleaving-tests`: use a started/release barrier rather than a sleep to hold the vulnerable boundary open.

## When to use

Use for fix stories involving reconnects, session replacement, duplicate admission, stale events, or UI state transitions:

1. Build the smallest realistic precondition that exposed the bug.
2. Assert the observable state at the vulnerable boundary.
3. Inject the stale, competing, or terminal event.
4. Assert both the repaired invariant and the allowed next transition.

## When not to use

Do not use this as a reason to encode implementation details or to duplicate ordinary happy-path tests. If no concrete before/after failure boundary exists, write a contract test instead.

## Examples

### Example 1: Hold concurrent authentication before releasing the factory

**File:** `app/test/transport/connection_manager_test.dart:152-176`

```dart
final first = cm.connectTo(_fakePeer());
await factoryStarted.future;
final second = cm.connectTo(_fakePeer());
await Future<void>.delayed(Duration.zero);

expect(
  factoryCalls,
  1,
  reason: 'one peer/room must have only one authenticating socket',
);

releaseFactory.complete();
await Future.wait([first, second]);
expect(cm.status, isA<StatusOnline>());
```

The test observes the in-flight boundary before releasing it, proving that a second request cannot create a duplicate socket.

### Example 2: Close the authoritative turn, then inject its late duplicate

**File:** `app/test/data/sync/sync_service_test.dart:1448-1485`

```dart
s.ch.push(UserInput(id: 'turn-one', text: 'first turn'));
await _settle();
expect(s.conn.isRoomWorking(s.epk, 'main'), isTrue);

s.ch.pushControl(
  RoomsSnapshot(
    peer: s.epk,
    rooms: [
      RoomInfo(
        roomId: 'main',
        sessionId: s.sessionId,
        startedAt: 1,
        working: false,
      ),
    ],
  ),
);
await _settle();
expect(s.conn.isRoomWorking(s.epk, 'main'), isFalse);

s.ch.push(UserInput(id: 'turn-one', text: 'first turn'));
await _settle();
expect(
  s.conn.isRoomWorking(s.epk, 'main'),
  isFalse,
  reason: 'the duplicate belongs to the turn closed by the snapshot',
);
```

The stale echo is injected only after the test establishes the authoritative idle state; the old implementation reopened the room here.

### Example 3: Preserve a send through the missing-session window

**File:** `app/test/ui/chat/chat_viewmodel_test.dart:828-865`

```dart
await vm.sendMessage('typed in the reconnect identity window');
await Future<void>.delayed(const Duration(milliseconds: 10));

var visible = (vm.state as ChatReady).messages.whereType<UserMsg>();
expect(visible, hasLength(1), reason: 'the send must never be absent');
expect(visible.single.status, UserMsgStatus.pending);
expect(ch.sent.whereType<UserMessage>(), isEmpty);

await Future<void>.delayed(const Duration(milliseconds: 600));
expect(visible.single.status, UserMsgStatus.failed);

ch.defaultSessionId = 'hydrated-session';
// Push the hydrated room snapshot, then assert the same row is resent.
```

The regression is expressed as a visible pending row before session identity exists, followed by the retry and identity-preserving confirmation after hydration.

## Common violations

- Asserting only the final green state, so the test would pass even if the original failure window returned.
- Triggering the race with arbitrary sleeps instead of an explicit barrier.
- Testing a private flag rather than the user-visible or wire-visible invariant.
- Accepting a duplicate row, socket, event, or notification because the final aggregate state looks correct.
