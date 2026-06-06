import 'package:cockpit/config/dependencies.dart';
import 'package:cockpit/routing/routes.dart';
import 'package:cockpit/ui/cockpit/cockpit_page.dart';
import 'package:cockpit/ui/cockpit/viewmodels/cockpit_viewmodel.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

/// Topologia de navegação. No MVP há só o shell do Cockpit; o `CockpitViewModel`
/// é provido aqui (o provider é dono do ciclo de vida → `dispose` mata as
/// sessões/processos vivos).
GoRouter buildRouter() {
  return GoRouter(
    initialLocation: RoutePaths.shell,
    routes: <RouteBase>[
      GoRoute(
        path: RoutePaths.shell,
        builder: (context, state) =>
            ChangeNotifierProvider<CockpitViewModel>(
              create: (_) => buildCockpitViewModel()..init(),
              child: const CockpitPage(),
            ),
      ),
    ],
  );
}
