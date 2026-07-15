import 'dart:async';
import 'dart:convert';

/// Split a byte stream into JSONL records for the `pi --mode rpc` protocol.
///
/// Uses LF (`\n`) as the only delimiter and strips a trailing `\r` to accept
/// CRLF input.
///
/// Do not replace this with [LineSplitter]. The RPC documentation warns that
/// generic line readers also split on Unicode separators (`U+2028`/`U+2029`),
/// which are valid inside JSON strings. This transformer splits only on `\n`.
///
/// Applies the chunked [utf8.decoder] first so multibyte sequences split across
/// chunks are reconstructed correctly.
class JsonlLineSplitter extends StreamTransformerBase<List<int>, String> {
  const JsonlLineSplitter();

  @override
  Stream<String> bind(Stream<List<int>> stream) async* {
    var buffer = '';
    await for (final text in stream.transform(utf8.decoder)) {
      buffer += text;
      var index = buffer.indexOf('\n');
      while (index != -1) {
        var line = buffer.substring(0, index);
        buffer = buffer.substring(index + 1);
        if (line.endsWith('\r')) {
          line = line.substring(0, line.length - 1);
        }
        if (line.isNotEmpty) yield line;
        index = buffer.indexOf('\n');
      }
    }
    final tail = buffer.endsWith('\r')
        ? buffer.substring(0, buffer.length - 1)
        : buffer;
    if (tail.isNotEmpty) yield tail;
  }
}
