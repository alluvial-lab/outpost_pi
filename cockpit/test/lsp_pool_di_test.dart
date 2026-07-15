import 'package:cockpit/app/core/core_module.dart';
import 'package:cockpit/app/core/data/lsp/lsp_server_pool.dart';
import 'package:cockpit/app/core/env.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';

/// Verify that `LspServerPool` and its `LspClientFactory` resolve through DI
/// from a feature. The auto_injector parser does not skip optional parameters
/// with defaults, so `ProjectRootFinder` cannot be a pool constructor parameter;
/// that regression previously failed while building the route.
void main() {
  testWidgets('LspServerPool resolves upward through core', (tester) async {
    final core = buildCoreModule(config: const PiSpawnConfig(executable: 'pi'));
    final feature = createModule(
      path: '/',
      register: (c) => c.route(
        '/',
        child: (ctx, s) => Text('lsp:${inject<LspServerPool>().runtimeType}'),
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

    expect(find.text('lsp:LspServerPool'), findsOneWidget);
  });
}
