import 'dart:async';
import 'dart:io';

import 'package:cockpit/app/core/data/lsp/lsp_server_pool.dart';
import 'package:cockpit/app/core/domain/contracts/lsp_client.dart';
import 'package:cockpit/app/core/domain/entities/lsp_diagnostic.dart';
import 'package:cockpit/app/core/domain/exceptions/lsp_error.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:flutter_test/flutter_test.dart';

/// Controllable fake client: the factory shares `startSucceeds` to simulate
/// "startup failed → command fixed → restart succeeds".
class _FakeClient implements LspClient {
  _FakeClient(this.rootPath, this._shared);
  final _Shared _shared;
  @override
  final String rootPath;

  final _diag = StreamController<LspDiagnosticsBatch>.broadcast();
  bool _running = false;
  final List<String> opened = [];

  @override
  Stream<LspDiagnosticsBatch> get diagnostics => _diag.stream;
  @override
  bool get isRunning => _running;

  @override
  Future<Result<void, LspError>> start() async {
    _shared.startCalls++;
    if (!_shared.startSucceeds) return const Failure(LspError('boom'));
    _running = true;
    return const Success(null);
  }

  @override
  Future<void> didOpen({required String path, required String text}) async =>
      opened.add(path);
  @override
  Future<void> didChange({
    required String path,
    required String text,
    required int version,
  }) async {}
  @override
  Future<void> didClose({required String path}) async {}
  @override
  Future<Result<Object?, LspError>> request(
    String method,
    Map<String, dynamic> params,
  ) async => const Success(null);
  @override
  Future<void> kill() async => _running = false;
  @override
  void dispose() {
    _diag.close();
  }
}

class _Shared {
  bool startSucceeds = true;
  int startCalls = 0;
  final List<_FakeClient> created = [];
}

class _FakeFactory implements LspClientFactory {
  _FakeFactory(this.shared);
  final _Shared shared;
  @override
  LspClient create({required LspServerSpec spec, required String rootPath}) {
    final c = _FakeClient(rootPath, shared);
    shared.created.add(c);
    return c;
  }
}

void main() {
  late Directory tmp;
  late String dartFile;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('pool_test');
    File('${tmp.path}/pubspec.yaml').writeAsStringSync('name: x');
    dartFile = '${tmp.path}/main.dart';
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test(
    'failed start on open → stopped; restart starts and reopens doc',
    () async {
      final shared = _Shared()..startSucceeds = false;
      final pool = LspServerPool(_FakeFactory(shared));

      await pool.openDocument(path: dartFile, text: 'a');
      // The server failed, but the doc remains registered → stopped (not null).
      final s1 = pool.statusForPath(dartFile);
      expect(s1, isNotNull);
      expect(s1!.running, isFalse);
      expect(s1.languageId, 'dart');

      // "Fix the command" and restart.
      shared.startSucceeds = true;
      await pool.restartForPath(dartFile);

      final s2 = pool.statusForPath(dartFile);
      expect(s2!.running, isTrue);
      // The doc was reopened on the new server.
      expect(shared.created.last.opened, contains(dartFile));

      pool.dispose();
    },
  );

  test('restartLanguage restarts even without a live server', () async {
    final shared = _Shared()..startSucceeds = false;
    final pool = LspServerPool(_FakeFactory(shared));
    await pool.openDocument(path: dartFile, text: 'a');
    expect(pool.statusForPath(dartFile)!.running, isFalse);

    shared.startSucceeds = true;
    await pool.restartLanguage('dart');
    expect(pool.statusForPath(dartFile)!.running, isTrue);

    pool.dispose();
  });

  test('successful open opens the doc and remains running', () async {
    final shared = _Shared();
    final pool = LspServerPool(_FakeFactory(shared));
    await pool.openDocument(path: dartFile, text: 'a');
    final s = pool.statusForPath(dartFile);
    expect(s!.running, isTrue);
    expect(shared.created.single.opened, [dartFile]);
    pool.dispose();
  });
}
