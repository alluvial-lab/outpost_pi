import 'package:xterm/xterm.dart';

/// Track whether the foreground program enabled the kitty keyboard protocol.
///
/// Supporting applications push flags with `CSI > flags u` on startup and pop
/// them with `CSI < n u` (or a reset) on exit. While flags are active, modified
/// keys such as Shift+Enter must use CSI-u rather than legacy encoding.
///
/// This tracker deliberately implements only enablement detection so
/// [ShiftEnterInputHandler] can choose the correct bytes. Every other key keeps
/// xterm's legacy encoding. It observes passively and never answers the
/// `CSI ? u` capability query, which prevents applications from enabling a
/// protocol that the rest of the keyboard path does not implement.
class KittyKeyboardTracker {
  final List<int> _stack = <int>[];
  String _carry = '';

  /// Report whether the foreground application has nonzero kitty flags active.
  bool get active => _stack.isNotEmpty && _stack.last > 0;

  /// Inspect a decoded PTY output chunk for kitty control sequences.
  ///
  /// The sequences are ASCII, so UTF-8 decoding does not alter them.
  void feed(String chunk) {
    // Preserve a short unmatched suffix because a kitty sequence may span reads.
    final s = _carry + chunk;
    var consumedEnd = 0;
    for (final m in _seqPattern.allMatches(s)) {
      _apply(m.group(0)!);
      consumedEnd = m.end;
    }
    final keepFrom = (s.length - _maxSeqLen) > consumedEnd
        ? s.length - _maxSeqLen
        : consumedEnd;
    _carry = keepFrom < s.length ? s.substring(keepFrom) : '';
  }

  void _apply(String seq) {
    if (seq == '\x1bc') {
      _stack.clear(); // RIS performs a full terminal reset.
      return;
    }
    // seq = ESC [ <marker> <0-9;>* u
    final marker = seq.codeUnitAt(2);
    final body = seq.substring(3, seq.length - 1);
    switch (marker) {
      case 0x3e: // '>' push: add a level with these flags.
        _stack.add(_firstInt(body));
      case 0x3c: // '<' pop: remove n levels (default 1).
        var n = _firstInt(body, fallback: 1);
        if (n < 1) n = 1;
        for (var i = 0; i < n && _stack.isNotEmpty; i++) {
          _stack.removeLast();
        }
      case 0x3d: // '=' set: flags ; mode (1=set, 2=or, 3=and-not; default 1).
        final parts = body.split(';');
        final flags = _intOr(parts.isNotEmpty ? parts[0] : '', 0);
        final mode = parts.length > 1 ? _intOr(parts[1], 1) : 1;
        final current = _stack.isEmpty ? 0 : _stack.removeLast();
        _stack.add(switch (mode) {
          2 => current | flags,
          3 => current & ~flags,
          _ => flags,
        });
      case 0x3f: // '?' query: ignore capability checks to stay passive.
        break;
    }
  }

  static int _firstInt(String body, {int fallback = 0}) =>
      _intOr(body.split(';').first, fallback);

  static int _intOr(String s, int fallback) => int.tryParse(s) ?? fallback;

  static const _maxSeqLen = 16;

  /// Match `CSI <marker> <0-9;>* u` or RIS (`ESC c`).
  static final _seqPattern = RegExp(r'\x1b\[[<>=?][0-9;]*u|\x1bc');
}

/// Make Shift+Enter insert a line break in TUI harnesses instead of submitting.
///
/// xterm 4.0 maps Shift+Enter to `ESC O M` (`\x1bOM`), which Claude, Codex,
/// and Pi ignore. This handler intercepts it before [defaultInputHandler] and
/// emits the encoding understood by the foreground application:
///
/// - with kitty keyboard active (Pi and Codex), canonical kitty Shift+Enter as
///   `CSI 13 ; 2 u` (`\x1b[13;2u`);
/// - otherwise (legacy Claude, shells, and REPLs), a line feed (`\n`) without
///   leaking CSI-u text into applications that do not support kitty.
///
/// Every key other than Shift+Enter falls through to the default handler.
class ShiftEnterInputHandler implements TerminalInputHandler {
  const ShiftEnterInputHandler(this._kitty);

  final KittyKeyboardTracker _kitty;

  @override
  String? call(TerminalKeyboardEvent event) {
    if (event.key != TerminalKey.enter ||
        !event.shift ||
        event.ctrl ||
        event.alt) {
      return null; // Let the default handler decide unless this is pure Shift+Enter.
    }
    return _kitty.active ? '\x1b[13;2u' : '\n';
  }
}
