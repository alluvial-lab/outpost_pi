import 'package:cockpit/app/cockpit/data/terminal/pty_terminal_gateway.dart';
import 'package:cockpit/app/cockpit/domain/contracts/terminal_gateway.dart';
import 'package:cockpit/app/cockpit/domain/contracts/terminal_gateway_factory.dart';

/// Create a dedicated [PtyTerminalGateway] for each terminal.
///
/// Each gateway independently owns its native PTY lifecycle.
class PtyTerminalGatewayFactory implements TerminalGatewayFactory {
  const PtyTerminalGatewayFactory();

  @override
  TerminalGateway create() => PtyTerminalGateway();
}
