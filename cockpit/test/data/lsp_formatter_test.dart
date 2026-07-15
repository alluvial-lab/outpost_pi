import 'dart:io';

import 'package:cockpit/app/core/data/lsp/lsp_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('runFormatterCommand', () {
    late File file;

    setUp(() {
      file = File('${Directory.systemTemp.createTempSync('fmt').path}/x.ts')
        ..writeAsStringSync('const a=1');
    });
    tearDown(() {
      if (file.parent.existsSync()) file.parent.deleteSync(recursive: true);
    });

    test('fails without the %FILE% placeholder', () async {
      final r = await runFormatterCommand('prettier --write', file.path);
      expect(r.isFailure, isTrue);
    });

    test('fails with an empty command', () async {
      final r = await runFormatterCommand('   ', file.path);
      expect(r.isFailure, isTrue);
    });

    test('succeeds when the command exits with code 0', () async {
      // `true` ignores arguments and exits with 0, exercising the happy path
      // without a real formatter or modifying the file.
      final r = await runFormatterCommand('true %FILE%', file.path);
      expect(r.isSuccess, isTrue);
    });

    test('fails when the command exits with a nonzero code', () async {
      final r = await runFormatterCommand('false %FILE%', file.path);
      expect(r.isFailure, isTrue);
    });
  });
}
