import 'package:cockpit/app/core/env.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';

/// Model a feature-level binding that depends on root-owned core configuration,
/// matching Cockpit factories and probes that consume `PiSpawnConfig`.
class _RpcLike {
  _RpcLike(this.config);
  final PiSpawnConfig config;
}

/// Verify flutter_modular 7.1.0 upward resolution at runtime.
///
/// A pathful feature module's `addLazySingleton<T>(T.new)` resolves its core
/// dependency upward. Earlier versions failed with "PiSpawnConfig not
/// registered" while building the route; this protects constructor-based graph
/// resolution from regressing to manually threaded `addInstance(X(config))`.
void main() {
  testWidgets(
    'feature addLazySingleton(.new) resolves core dependency upward',
    (tester) async {
      final core = createModule(
        register: (c) =>
            c.addInstance<PiSpawnConfig>(const PiSpawnConfig(executable: 'pi')),
      );
      final feature = createModule(
        path: '/',
        register: (c) => c
          ..addLazySingleton<_RpcLike>(_RpcLike.new)
          ..route(
            '/',
            child: (ctx, s) =>
                Text('exe:${inject<_RpcLike>().config.executable}'),
          ),
      );
      final app = createModule(
        register: (c) => c
          ..module(core)
          ..module(feature),
      );

      final boot = bootstrapModule(app);
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: modularRouterConfig(
            boot.routes,
            injector: boot.injector,
            manager: boot.manager,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Reaching this assertion proves upward resolution: otherwise route build
      // would fail with "PiSpawnConfig not registered" before rendering.
      expect(find.text('exe:pi'), findsOneWidget);
    },
  );
}
