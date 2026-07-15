import 'package:cockpit/app/cockpit/domain/contracts/terminal_gateway.dart';

/// Create PTYs with **one gateway per terminal**.
///
/// This domain contract is implemented in `data/`.
abstract class TerminalGatewayFactory {
  TerminalGateway create();
}
