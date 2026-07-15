import 'package:cockpit/app/cockpit/domain/contracts/rpc_process_gateway.dart';

/// Create RPC gateways with **one gateway per agent** for Wave 2 multiplexing.
///
/// The `data/` implementation constructs a new `PiRpcProcess` on every call.
/// Agent sessions in `ui/` request gateways here instead of instantiating
/// `data/` directly, preserving the `ui → domain ← data` dependency flow.
abstract class RpcGatewayFactory {
  RpcProcessGateway create();
}
