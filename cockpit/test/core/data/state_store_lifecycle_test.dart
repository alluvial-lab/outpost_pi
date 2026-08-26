import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:cockpit/app/core/domain/contracts/state_store.dart';
import 'package:cockpit/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('requested exit awaits every pending state-store flush', () async {
    final release = Completer<void>();
    final factory = _ControlledFactory(release.future);
    final observer = StateStoreExitObserver(factory);
    var completed = false;

    final response = observer.didRequestAppExit();
    unawaited(response.then((_) => completed = true));
    await Future<void>.delayed(Duration.zero);

    expect(factory.flushCalls, 1);
    expect(completed, isFalse);

    release.complete();
    expect(await response, AppExitResponse.exit);
    expect(completed, isTrue);
  });
}

final class _ControlledFactory implements StateStoreFactory {
  _ControlledFactory(this._flush);

  final Future<void> _flush;
  int flushCalls = 0;

  @override
  Future<StateStore> open(String name) =>
      throw UnsupportedError('open is not part of this lifecycle test');

  @override
  Future<void> flushAll() async {
    flushCalls++;
    await _flush;
  }
}
