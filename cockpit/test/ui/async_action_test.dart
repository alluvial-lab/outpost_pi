import 'dart:async';

import 'package:cockpit/app/core/ui/async_action.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'ownAsync forwards a failed future to the originating zone once',
    () async {
      final errors = <Object>[];
      final stacks = <StackTrace>[];

      runZonedGuarded(
        () {
          ownAsync(
            Future<void>.error(StateError('failed'), StackTrace.current),
          );
        },
        (error, stackTrace) {
          errors.add(error);
          stacks.add(stackTrace);
        },
      );
      await pumpEventQueue();

      expect(errors, hasLength(1));
      expect(errors.single, isA<StateError>());
      expect(stacks.single, isNot(StackTrace.empty));
    },
  );

  test('ownAsync success produces no zone notification', () async {
    final errors = <Object>[];

    runZonedGuarded(
      () => ownAsync(Future<void>.value()),
      (error, _) => errors.add(error),
    );
    await pumpEventQueue();

    expect(errors, isEmpty);
  });

  test(
    'ownedAsyncAction invokes its action exactly once per callback',
    () async {
      var calls = 0;
      final callback = ownedAsyncAction(() async {
        calls++;
      });

      callback();
      await pumpEventQueue();

      expect(calls, 1);
    },
  );

  test('ownedAsyncAction preserves synchronous exceptions', () {
    final callback = ownedAsyncAction(() {
      throw StateError('synchronous');
    });

    expect(callback, throwsA(isA<StateError>()));
  });
}
