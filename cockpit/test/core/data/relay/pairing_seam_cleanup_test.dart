import 'dart:io';

import 'package:cockpit/app/core/data/relay/pairing_seam_cleanup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('removes an abandoned private pairing seam only', () async {
    final root = await Directory.systemTemp.createTemp('pair-sweep-test-');
    addTearDown(() async {
      if (root.existsSync()) await root.delete(recursive: true);
    });

    final abandoned = await root.createTemp('outpost-pi-pair-abandoned-');
    await File(
      '${abandoned.path}${Platform.pathSeparator}pair-code.json',
    ).writeAsString('{"token":"still-valid"}');
    if (!Platform.isWindows) {
      await Process.run('chmod', ['700', abandoned.path]);
    }
    final unrelated = await Directory(
      '${root.path}${Platform.pathSeparator}not-a-pair-seam',
    ).create();

    final removed = await PairingSeamCleanup.sweep(tempDirectory: root);

    expect(removed, 1);
    expect(abandoned.existsSync(), isFalse);
    expect(unrelated.existsSync(), isTrue);
  });
}
