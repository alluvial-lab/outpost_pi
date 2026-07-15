import 'package:cockpit/app/settings/data/daemon/supervisor_client_impl.dart';
import 'package:cockpit/app/settings/data/relay/relay_gateway_impl.dart';
import 'package:cockpit/app/settings/domain/contracts/cron_gateway.dart';
import 'package:cockpit/app/settings/domain/contracts/daemon_supervisor.dart';
import 'package:cockpit/app/settings/domain/contracts/relay_gateway.dart';
import 'package:cockpit/app/settings/ui/connectivity_viewmodel.dart';
import 'package:cockpit/app/settings/ui/cron_viewmodel.dart';
import 'package:cockpit/app/settings/ui/daemons_viewmodel.dart';
import 'package:cockpit/app/settings/ui/notifications_viewmodel.dart';
import 'package:cockpit/app/settings/ui/settings_env_gate.dart';
import 'package:cockpit/app/settings/ui/settings_page.dart';
import 'package:flutter_modular/flutter_modular.dart';

/// Build the stacked `/settings` feature for connectivity, daemons, and cron.
///
/// Registers one [SupervisorClientImpl] under both [DaemonSupervisor] and
/// [CronGateway] because they share the `pi-supervisord` control-plane UDS.
/// ViewModels are page-scoped through `provide` and disposed when the route
/// closes. The root-owned core injects `PairingGatewayFactory` and
/// `RevokeGatewayFactory` into `ConnectivityViewModel`; those factories spawn
/// an ephemeral `pi --mode rpc` for pairing and revocation.
Module buildSettingsModule() => createModule(
  path: '/settings',
  register: (c) {
    final supervisor = SupervisorClientImpl();
    c
      ..addSingleton<RelayGateway>(RelayGatewayImpl.new)
      ..addInstance<DaemonSupervisor>(supervisor)
      ..addInstance<CronGateway>(supervisor)
      ..route(
        '/',
        transition: TransitionType.fade,
        provide: (s) => s
          ..addChangeNotifier<ConnectivityViewModel>(ConnectivityViewModel.new)
          ..addChangeNotifier<DaemonsViewModel>(DaemonsViewModel.new)
          ..addChangeNotifier<CronViewModel>(CronViewModel.new)
          // Resolve core dependencies upward from the page scope:
          // EnvironmentProbe and SystemPermissions.
          ..addChangeNotifier<SettingsEnvGate>(SettingsEnvGate.new)
          ..addChangeNotifier<NotificationsViewModel>(
            NotificationsViewModel.new,
          ),
        child: (context, state) => const SettingsPage(),
      );
  },
);
