import 'dart:async';
import 'dart:convert';

import 'package:cockpit/app/cockpit/domain/contracts/terminal_gateway.dart';
import 'package:cockpit/app/cockpit/ui/session/pane_item.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_input.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:xterm/xterm.dart';

/// Own a terminal tab that connects a PTY shell to an xterm [Terminal].
///
/// `TerminalView` renders [terminal], while this session owns the gateway and
/// kills the PTY during [close] so no child process is orphaned.
class TerminalSession extends PaneItem {
  TerminalSession({
    required this.id,
    required this.projectId,
    required this.workingDirectory,
    required TerminalGateway gateway,
    String? title,
  }) : _gateway = gateway,
       _title = title ?? 'New terminal' {
    // Handle Shift+Enter before xterm's default so TUI harnesses receive a line
    // break instead of submit; `_kitty` tracks protocol state from PTY output.
    terminal = Terminal(
      maxLines: 10000,
      inputHandler: CascadeInputHandler([
        ShiftEnterInputHandler(_kitty),
        defaultInputHandler,
      ]),
    );

    // Start the shell and connect both directions. The cast adapts the PTY's
    // Uint8List stream for streaming UTF-8 decoding across chunk boundaries.
    try {
      _gateway.start(workingDirectory: workingDirectory, rows: 25, columns: 80);
    } catch (error) {
      _startupError = 'Could not start the terminal: $error';
      terminal.write('\u001b[31m$_startupError\u001b[0m\r\n');
      return;
    }
    final spawn = _gateway is TerminalSpawnDirectory
        ? (_gateway as TerminalSpawnDirectory).spawnDirectory
        : null;
    if (spawn?.fellBack ?? false) {
      _startupError =
          'Workspace directory "${spawn!.requested}" is missing. '
          'The terminal opened in "${spawn.path}".';
      terminal.write('\u001b[31m$_startupError\u001b[0m\r\n');
    }
    _sub = _gateway.output
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((data) {
          _kitty.feed(data); // Observe kitty push/pop before rendering.
          terminal.write(data);
        });
    terminal.onOutput = (data) => _gateway.write(utf8.encode(data));
    terminal.onResize = (width, height, pixelWidth, pixelHeight) =>
        _gateway.resize(height, width);
    // Reflect OSC 0/2 window titles from shells, editors, or SSH in the tab.
    terminal.onTitleChange = (osc) => rename(_shortTitle(osc));
  }

  /// Shorten path-like window titles to their last segment for the tab.
  ///
  /// Preserve `~` and non-path titles; the tab still applies ellipsis.
  String _shortTitle(String raw) {
    final t = raw.trim();
    if (t.isEmpty || !t.contains('/')) return t;
    final segments = t.split('/').where((s) => s.isNotEmpty).toList();
    return segments.isEmpty ? t : segments.last;
  }

  @override
  final String id;
  @override
  final String projectId;
  @override
  final String workingDirectory;

  final TerminalGateway _gateway;
  final KittyKeyboardTracker _kitty = KittyKeyboardTracker();
  String? _startupError;
  String _title;
  late final Terminal terminal;
  StreamSubscription<String>? _sub;

  @override
  String get title => _title;

  /// Describe a terminal recovery or startup failure, if one was surfaced.
  String? get startupError => _startupError;

  void rename(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty || trimmed == _title) return;
    _title = trimmed;
    notifyListeners();
  }

  /// Insert [text] directly into the PTY as typed or pasted input.
  ///
  /// This supports inputs such as a file path dropped onto the terminal.
  void insertText(String text) => _gateway.write(utf8.encode(text));

  /// Paste clipboard text or forward an image paste to the foreground harness.
  ///
  /// For an image, write the Ctrl+V byte (`\x16`) so Claude, Codex, or Pi reads
  /// and attaches the image from the clipboard. Otherwise use xterm's normal
  /// text paste so bracketed-paste mode is respected.
  ///
  /// This bypasses `TerminalView`'s text-only clipboard path and the macOS IME
  /// path that converts raw Ctrl+V to `pageDown` before it reaches the PTY.
  Future<void> pasteFromClipboard() async {
    final image = await Pasteboard.image;
    if (image != null && image.isNotEmpty) {
      _gateway.write(const [
        0x16,
      ]); // Ctrl+V tells the foreground harness to read the clipboard image.
      return;
    }
    final text = await Pasteboard.text;
    if (text != null && text.isNotEmpty) terminal.paste(text);
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    _sub = null;
    await _gateway.kill();
    await super.close();
  }
}
