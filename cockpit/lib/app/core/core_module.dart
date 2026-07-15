import 'package:cockpit/app/core/data/lsp/lsp_client_impl.dart';
import 'package:cockpit/app/core/data/lsp/lsp_server_pool.dart';
import 'package:cockpit/app/core/data/relay/pairing_gateway_impl.dart';
import 'package:cockpit/app/core/data/relay/revoke_gateway_impl.dart';
import 'package:cockpit/app/core/data/setup/environment_probe_impl.dart';
import 'package:cockpit/app/core/data/setup/system_permissions_impl.dart';
import 'package:cockpit/app/core/domain/contracts/environment_probe.dart';
import 'package:cockpit/app/core/domain/contracts/lsp_client.dart';
import 'package:cockpit/app/core/domain/contracts/pairing_gateway.dart';
import 'package:cockpit/app/core/domain/contracts/revoke_gateway.dart';
import 'package:cockpit/app/core/domain/contracts/system_permissions.dart';
import 'package:cockpit/app/core/env.dart';
import 'package:flutter_modular/flutter_modular.dart';

/// Build the cross-cutting kernel as a pathless, root-owned module.
///
/// Shared bindings and bindings whose constructors resolve other core
/// dependencies live here. Root ownership keeps them alive for the entire app
/// rather than disposing them during navigation.
///
/// - [PiSpawnConfig] configures both Cockpit RPC sessions and ephemeral pairing
///   or revoke processes.
/// - [PairingGatewayFactory] and [RevokeGatewayFactory] resolve that config in
///   the same root scope and remain visible to page-scoped settings state.
/// - `SettingsStore` and `SettingsController` are built before the first frame
///   in `main`, so they deliberately do not enter this graph.
/// - [LspServerPool] is shared across workspaces for document and diagnostic
///   routing.
/// - [EnvironmentProbe] and [SystemPermissions] serve setup surfaces in both
///   features; [EnvironmentProbeImpl] resolves [PiSpawnConfig] here.
Module buildCoreModule({required PiSpawnConfig config}) => createModule(
  register: (c) => c
    ..addInstance<PiSpawnConfig>(config)
    ..addInstance<LspClientFactory>(const LspClientFactoryImpl())
    ..addLazySingleton<LspServerPool>(LspServerPool.new)
    ..add<PairingGatewayFactory>(PairingGatewayFactoryImpl.new)
    ..add<RevokeGatewayFactory>(RevokeGatewayFactoryImpl.new)
    ..addLazySingleton<EnvironmentProbe>(EnvironmentProbeImpl.new)
    ..addInstance<SystemPermissions>(SystemPermissionsImpl()),
);
