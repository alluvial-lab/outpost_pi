import 'package:cockpit/app/core/env.dart';
import 'package:cockpit/app/cockpit/data/rpc/pi_rpc_process.dart';
import 'package:cockpit/app/cockpit/domain/contracts/rpc_gateway_factory.dart';
import 'package:cockpit/app/cockpit/domain/contracts/rpc_process_gateway.dart';

/// Create a dedicated [PiRpcProcess] for each agent.
///
/// Keeping one process per gateway preserves independent process lifecycle and
/// request correlation when multiple agents run concurrently.
class PiRpcProcessFactory implements RpcGatewayFactory {
  const PiRpcProcessFactory(this._config);

  final PiSpawnConfig _config;

  @override
  RpcProcessGateway create() => PiRpcProcess(_config);
}
