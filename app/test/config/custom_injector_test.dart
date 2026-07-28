import 'package:app/config/utils/injector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('disposes an owned instance callback exactly once', () {
    final injector = CustomInjector();
    final resource = _DisposableResource();

    injector.addInstance<_DisposableResource>(
      resource,
      onDispose: (value) => value.dispose(),
    );

    injector.dispose();
    injector.dispose();

    expect(resource.disposeCalls, 1);
  });
}

final class _DisposableResource {
  int disposeCalls = 0;

  void dispose() => disposeCalls += 1;
}
