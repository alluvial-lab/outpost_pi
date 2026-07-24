import 'dart:io';

import 'package:cockpit/app/core/data/lsp/lsp_client_impl.dart';
import 'package:cockpit/app/core/domain/contracts/lsp_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _waitUntil(bool Function() condition, {String? reason}) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail(reason ?? 'condition did not become true');
}

void main() {
  test('stderr diagnostics keep only a count and exit code', () async {
    const secret = '/Users/operator/project/lib/main.dart token=secret-7F3A';
    final root = Directory.systemTemp.createTempSync('lsp_client_impl_test');
    final output = <String>[];
    final originalDebugPrint = debugPrint;
    final client = LspClientImpl(
      spec: LspServerSpec(
        languageId: 'test-language',
        executable: 'sh',
        args: <String>[
          '-c',
          '''
IFS= read -r _
IFS= read -r _
printf 'Content-Length: 38\r\n\r\n{"jsonrpc":"2.0","id":1,"result":null}'
printf '%s\n' '$secret' >&2
printf '%s\n' '$secret again' >&2
exit 17
''',
        ],
      ),
      rootPath: root.path,
    );

    debugPrint = (message, {wrapWidth}) {
      if (message != null) output.add(message);
    };
    try {
      final started = await client.start();
      expect(started.isSuccess, isTrue);
      await _waitUntil(
        () => output.any((line) => line.contains('exited code=17')),
        reason: 'language server exit diagnostic',
      );
    } finally {
      debugPrint = originalDebugPrint;
      client.dispose();
      root.deleteSync(recursive: true);
    }

    final diagnosticText = output.join('\n');
    expect(
      output.where(
        (line) =>
            line ==
            '[lsp:test-language][err] server diagnostic output '
                '(content hidden)',
      ),
      hasLength(1),
    );
    expect(
      diagnosticText,
      contains('[lsp:test-language] exited code=17 stderrLines=2'),
    );
    expect(diagnosticText, isNot(contains(secret)));
    expect(diagnosticText, isNot(contains('/Users/operator/project')));
    expect(diagnosticText, isNot(contains('token=secret-7F3A')));
  });
}
