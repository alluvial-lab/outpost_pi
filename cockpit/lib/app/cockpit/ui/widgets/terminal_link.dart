import 'package:xterm/xterm.dart';

/// Describe a URL and its column range within one terminal buffer line.
///
/// The range drives hover highlighting and click-to-open behavior.
class TerminalLink {
  const TerminalLink({
    required this.url,
    required this.row,
    required this.startCol,
    required this.endCol, // exclusivo
  });

  final String url;
  final int row;
  final int startCol;
  final int endCol;

  bool contains(int col) => col >= startCol && col < endCol;
}

/// Find the URL beneath a terminal cell.
///
/// Explicit OSC 8 hyperlinks take precedence. Otherwise detect URLs by regex over
/// rendered terminal text, as terminal emulators conventionally do.
class TerminalLinkDetector {
  // Match http(s)://, file://, and www., stopping at whitespace or common closing
  // punctuation that does not belong to a URL.
  static final _urlRegex = RegExp(
    r'''(?:https?://|file://|www\.)[^\s<>()\[\]{}"'`]+''',
    caseSensitive: false,
  );

  // Strip sentence-ending punctuation commonly adjacent to a URL.
  static const _trailingTrim = '.,;:!?';

  TerminalLink? linkAt(Terminal terminal, CellOffset pos) {
    final lines = terminal.buffer.lines;
    if (pos.y < 0 || pos.y >= lines.length) return null;
    final line = lines[pos.y];
    final cols = line.length;
    if (cols <= 0 || pos.x < 0 || pos.x >= cols) return null;

    // Prefer explicit OSC 8 application hyperlinks over regex guesses. Extend
    // through the contiguous cells carrying the same URL.
    if (line.getCodePoint(pos.x) != 0) {
      final url = terminal.hyperlinkUrl(line.getAttributes(pos.x));
      if (url != null && url.isNotEmpty) {
        var start = pos.x;
        var end = pos.x + 1;
        while (start > 0 &&
            terminal.hyperlinkUrl(line.getAttributes(start - 1)) == url) {
          start--;
        }
        while (end < cols &&
            terminal.hyperlinkUrl(line.getAttributes(end)) == url) {
          end++;
        }
        return TerminalLink(url: url, row: pos.y, startCol: start, endCol: end);
      }
    }

    // Build a column-indexed string: empty/spacer cells become spaces that break
    // URLs, while real characters retain their columns. URLs are single-width
    // ASCII, so regex offsets map directly to columns.
    final units = List<int>.filled(cols, 0x20);
    for (var c = 0; c < cols; c++) {
      final code = line.getCodePoint(c);
      if (code != 0) units[c] = code;
    }
    final text = String.fromCharCodes(units);

    for (final m in _urlRegex.allMatches(text)) {
      if (pos.x < m.start || pos.x >= m.end) continue;
      var end = m.end;
      // Trim trailing punctuation unless the pointer is directly over it.
      while (end - 1 > m.start &&
          end - 1 > pos.x &&
          _trailingTrim.contains(text[end - 1])) {
        end--;
      }
      return TerminalLink(
        url: text.substring(m.start, end),
        row: pos.y,
        startCol: m.start,
        endCol: end,
      );
    }
    return null;
  }
}
