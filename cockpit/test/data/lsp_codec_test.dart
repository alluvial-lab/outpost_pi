import 'dart:async';
import 'dart:convert';

import 'package:cockpit/app/core/data/lsp/lsp_codec.dart';
import 'package:flutter_test/flutter_test.dart';

/// LSP framing bytes for a JSON-RPC message.
List<int> frame(Map<String, dynamic> json) => encodeLspMessage(json);

Future<List<Map<String, dynamic>>> decodeChunks(List<List<int>> chunks) {
  return Stream<List<int>>.fromIterable(
    chunks,
  ).transform(const LspMessageDecoder()).toList();
}

void main() {
  group('LspMessageDecoder', () {
    test('round-trips one message', () async {
      final msg = {'jsonrpc': '2.0', 'id': 1, 'method': 'initialize'};
      final out = await decodeChunks([frame(msg)]);
      expect(out, hasLength(1));
      expect(out.first['method'], 'initialize');
      expect(out.first['id'], 1);
    });

    test('encode uses UTF-8 bytes, not chars, for Content-Length', () {
      final bytes = encodeLspMessage({'msg': 'café'}); // 'é' = 2 UTF-8 bytes.
      final all = ascii.decode(bytes, allowInvalid: true);
      final body = utf8.encode(jsonEncode({'msg': 'café'}));
      expect(all, contains('Content-Length: ${body.length}\r\n\r\n'));
    });

    test('two messages in the same chunk', () async {
      final a = frame({'id': 1});
      final b = frame({'id': 2});
      final out = await decodeChunks([
        [...a, ...b],
      ]);
      expect(out.map((m) => m['id']), [1, 2]);
    });

    test('message fragmented across multiple chunks', () async {
      final full = frame({'jsonrpc': '2.0', 'method': 'x', 'n': 42});
      // Split in the middle of the body.
      final cut = full.length - 3;
      final out = await decodeChunks([full.sublist(0, cut), full.sublist(cut)]);
      expect(out, hasLength(1));
      expect(out.first['n'], 42);
    });

    test('body with multibyte UTF-8 counts bytes correctly', () async {
      final msg = {'message': 'olá 世界 🚀'};
      final out = await decodeChunks([frame(msg)]);
      expect(out, hasLength(1));
      expect(out.first['message'], 'olá 世界 🚀');
    });

    test('header is case-insensitive', () async {
      final body = utf8.encode(jsonEncode({'ok': true}));
      final raw = <int>[
        ...ascii.encode('content-length: ${body.length}\r\n\r\n'),
        ...body,
      ];
      final out = await decodeChunks([raw]);
      expect(out, hasLength(1));
      expect(out.first['ok'], true);
    });

    test('invalid JSON is discarded without blocking the stream', () async {
      final bad = utf8.encode('{not json');
      final raw = <int>[
        ...ascii.encode('Content-Length: ${bad.length}\r\n\r\n'),
        ...bad,
      ];
      final good = frame({'id': 9});
      final out = await decodeChunks([
        [...raw, ...good],
      ]);
      // The invalid message disappears; the valid one passes through.
      expect(out.map((m) => m['id']), [9]);
    });
  });
}
