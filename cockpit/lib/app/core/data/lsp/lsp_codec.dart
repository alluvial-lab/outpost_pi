import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// Decode LSP stdio framing into JSON messages.
///
/// Each message is framed as
/// `Content-Length: <N>\r\n\r\n<N bytes of UTF-8 JSON>`. This differs from pi's
/// JSONL framing (one line per message), so it cannot reuse
/// `JsonlLineSplitter`.
///
/// Consumes raw server stdout bytes and emits each decoded JSON object as a
/// `Map<String, dynamic>`. It buffers input because a stdout chunk may contain
/// a partial message or several messages.
///
/// Use [encodeLspMessage] to write messages.
class LspMessageDecoder
    extends StreamTransformerBase<List<int>, Map<String, dynamic>> {
  const LspMessageDecoder();

  @override
  Stream<Map<String, dynamic>> bind(Stream<List<int>> stream) {
    final buffer = BytesBuilder(copy: false);
    // Keep accumulated content as bytes. Headers are parsed as ASCII and the
    // body as UTF-8; JSON may contain multibyte sequences, so lengths count
    // bytes rather than characters.
    List<int> pending = const <int>[];

    return stream.transform(
      StreamTransformer<List<int>, Map<String, dynamic>>.fromHandlers(
        handleData: (chunk, sink) {
          buffer.add(chunk);
          pending = buffer.takeBytes();
          // Drain every complete message currently in the buffer.
          while (true) {
            final message = _tryParseOne(pending);
            if (message == null) break;
            pending = message.rest;
            if (message.json != null) sink.add(message.json!);
          }
          // Return the incomplete remainder to the buffer for the next chunk.
          buffer.add(pending);
          pending = const <int>[];
        },
      ),
    );
  }
}

/// Hold one parse attempt's message and remaining bytes.
///
/// The message is `null` when the framed body is invalid.
class _ParsedMessage {
  const _ParsedMessage(this.json, this.rest);
  final Map<String, dynamic>? json;
  final List<int> rest;
}

const int _cr = 13; // \r
const int _lf = 10; // \n

/// Extract one message from [data].
///
/// Returns `null` until a complete header and body are available.
_ParsedMessage? _tryParseOne(List<int> data) {
  // Find the end of the header block: \r\n\r\n.
  final headerEnd = _indexOfHeaderTerminator(data);
  if (headerEnd < 0) return null;

  final headerBytes = data.sublist(0, headerEnd);
  final headers = ascii.decode(headerBytes, allowInvalid: true);
  final contentLength = _contentLengthOf(headers);
  final bodyStart = headerEnd + 4; // Skip \r\n\r\n.

  if (contentLength == null) {
    // Discard a header block without a valid Content-Length and continue.
    return _ParsedMessage(null, data.sublist(bodyStart));
  }
  if (data.length - bodyStart < contentLength) return null; // Incomplete body.

  final bodyBytes = data.sublist(bodyStart, bodyStart + contentLength);
  final rest = data.sublist(bodyStart + contentLength);
  try {
    final decoded = jsonDecode(utf8.decode(bodyBytes));
    if (decoded is Map<String, dynamic>) return _ParsedMessage(decoded, rest);
    return _ParsedMessage(null, rest);
  } catch (_) {
    return _ParsedMessage(null, rest);
  }
}

/// Find the start of `\r\n\r\n` in [data], or return -1.
int _indexOfHeaderTerminator(List<int> data) {
  for (var i = 0; i + 3 < data.length; i++) {
    if (data[i] == _cr &&
        data[i + 1] == _lf &&
        data[i + 2] == _cr &&
        data[i + 3] == _lf) {
      return i;
    }
  }
  return -1;
}

/// Read `Content-Length` from the header block, case-insensitively.
int? _contentLengthOf(String headers) {
  for (final line in headers.split('\r\n')) {
    final idx = line.indexOf(':');
    if (idx < 0) continue;
    final name = line.substring(0, idx).trim().toLowerCase();
    if (name == 'content-length') {
      return int.tryParse(line.substring(idx + 1).trim());
    }
  }
  return null;
}

/// Encode a JSON-RPC message with LSP framing, ready for stdin.
List<int> encodeLspMessage(Map<String, dynamic> message) {
  final body = utf8.encode(jsonEncode(message));
  final header = ascii.encode('Content-Length: ${body.length}\r\n\r\n');
  return <int>[...header, ...body];
}
