import 'dart:async';
import 'dart:convert';

import 'package:cockpit/domain/contracts/terminal_gateway.dart';
import 'package:cockpit/ui/cockpit/session/pane_item.dart';
import 'package:xterm/xterm.dart';

/// Uma aba de terminal: um shell num PTY ([TerminalGateway]) ligado a um
/// emulador [Terminal] do xterm. O `TerminalView` (na PaneView) renderiza
/// `terminal`. Mata o PTY no `dispose` (sem órfão).
class TerminalSession extends PaneItem {
  TerminalSession({
    required this.id,
    required this.projectId,
    required this.workingDirectory,
    required TerminalGateway gateway,
    String? title,
  }) : _gateway = gateway,
       _title = title ?? 'Terminal' {
    terminal = Terminal(maxLines: 10000);

    // Sobe o shell e liga os dois lados. O `.cast<List<int>>()` re-vincula o
    // tipo do stream (o PTY emite Uint8List) para o `utf8.decoder` aceitar e
    // decodificar em streaming (trata multibyte partido entre chunks).
    _gateway.start(workingDirectory: workingDirectory, rows: 25, columns: 80);
    _sub = _gateway.output
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(terminal.write);
    terminal.onOutput = (data) => _gateway.write(utf8.encode(data));
    terminal.onResize = (width, height, pixelWidth, pixelHeight) =>
        _gateway.resize(height, width);
  }

  @override
  final String id;
  @override
  final String projectId;
  @override
  final String workingDirectory;

  final TerminalGateway _gateway;
  String _title;
  late final Terminal terminal;
  StreamSubscription<String>? _sub;

  @override
  String get title => _title;

  void rename(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty || trimmed == _title) return;
    _title = trimmed;
    notifyListeners();
  }

  @override
  Future<void> dispose() async {
    await _sub?.cancel();
    await _gateway.kill();
    super.dispose();
  }
}
