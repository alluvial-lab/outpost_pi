import 'dart:async';
import 'dart:io';

import 'package:cockpit/app/core/data/lsp/lsp_command.dart';
import 'package:cockpit/app/core/data/lsp/lsp_launchers.dart';
import 'package:cockpit/app/core/data/lsp/lsp_text_edit.dart';
import 'package:cockpit/app/core/data/lsp/project_root_finder.dart';
import 'package:cockpit/app/core/domain/contracts/lsp_client.dart';
import 'package:cockpit/app/core/domain/entities/lsp_diagnostic.dart';
import 'package:cockpit/app/core/domain/exceptions/lsp_error.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/core/utils/executable_resolver.dart';
import 'package:flutter/foundation.dart';

/// Share language servers across the entire app, keyed by `(language, root)`.
///
/// Multiple live workspaces use this pool: two files under the same root reuse
/// one server, while distinct roots or languages use distinct servers.
///
/// Manages lifecycle through open-document reference counting. The last
/// `closeDocument` schedules shutdown after a grace period in case the user
/// quickly reopens a file. It degrades gracefully: a language without an
/// installed server is a silent no-op and never breaks the editor.
class LspServerPool {
  LspServerPool(this._factory);

  final LspClientFactory _factory;
  // Keep this outside DI because auto_injector's parser does not skip an
  // optional parameter with a default value.
  final ProjectRootFinder _rootFinder = const ProjectRootFinder();

  final Map<String, _ServerEntry> _servers = <String, _ServerEntry>{};
  final Map<String, _DocEntry> _docs = <String, _DocEntry>{};

  final StreamController<LspDiagnosticsBatch> _diagnostics =
      StreamController<LspDiagnosticsBatch>.broadcast();

  /// Emit whenever a server starts, stops, or restarts.
  ///
  /// The LSP status bar listens to these pulses to refresh its live indicator.
  final StreamController<void> _statusChanges =
      StreamController<void>.broadcast();

  /// Merge diagnostics from every server; the UI routes batches by `uri`.
  Stream<LspDiagnosticsBatch> get diagnostics => _diagnostics.stream;

  /// Emit payload-free server-state changes so the UI rechecks [statusForPath].
  Stream<void> get statusChanges => _statusChanges.stream;

  /// Override commands by language from the Wave 2 Language screen.
  ///
  /// Maps `languageId` to a command line (`exec arg1 arg2`). An empty value uses
  /// the default command.
  Map<String, String> commandOverrides = const <String, String>{};

  /// Grace period before shutting down a server with no open documents.
  static const Duration _shutdownGrace = Duration(seconds: 30);

  /// Open a document and attach it to its language server.
  ///
  /// Resolves the language/root, records the document even when the server
  /// fails to start so restart can reopen it, starts or reuses the server, and
  /// sends `didOpen`. Uses the workspace [fallbackRoot] when the upward marker
  /// search finds no root. Unsupported languages are a no-op.
  Future<void> openDocument({
    required String path,
    required String text,
    String? fallbackRoot,
  }) async {
    final def = languageForPath(path);
    if (def == null) return;
    final root = _rootFinder.findRoot(path, def.markers) ?? fallbackRoot;
    if (root == null) return;

    final key = _key(def.id, root);
    // Record the document before startup so statusForPath/restart retain its
    // text and root even if startup fails.
    _docs[path] = _DocEntry(key, root, text);
    final entry = await _ensureServer(key, def, root);
    if (entry != null && entry.client.isRunning) {
      await entry.client.didOpen(path: path, text: text);
    }
  }

  /// Ensure [key] has a live server.
  ///
  /// Reuses an existing server or resolves its specification and starts one.
  /// Returns the live entry, or `null` when startup fails; documents remain
  /// recorded and their status stays stopped for graceful degradation.
  Future<_ServerEntry?> _ensureServer(
    String key,
    LanguageDef def,
    String root,
  ) async {
    final existing = _servers[key];
    if (existing != null) {
      existing.cancelPendingShutdown();
      return existing.client.isRunning ? existing : null;
    }
    final spec = await _resolveSpec(def);
    if (spec == null) {
      _statusChanges.add(null);
      return null;
    }
    final client = _factory.create(spec: spec, rootPath: root);
    final entry = _ServerEntry(client);
    _servers[key] = entry;
    entry.sub = client.diagnostics.listen(_onDiagnostics);
    final result = await client.start();
    if (result.isFailure) {
      debugPrint('[lsp-pool] start failed ($key)');
      await entry.sub?.cancel();
      _servers.remove(key);
      client.dispose();
      _statusChanges.add(null);
      return null;
    }
    _statusChanges.add(null);
    return entry;
  }

  /// Send a full-sync `textDocument/didChange` notification.
  ///
  /// Retains the text without a live server so restart can reopen the current
  /// content.
  Future<void> changeDocument({
    required String path,
    required String text,
  }) async {
    final doc = _docs[path];
    if (doc == null) return;
    doc.version++;
    doc.lastText = text;
    final entry = _servers[doc.serverKey];
    if (entry == null || !entry.client.isRunning) return;
    await entry.client.didChange(path: path, text: text, version: doc.version);
  }

  /// Report the language and server state for the document at [path].
  ///
  /// Returns `null` for an unsupported language so the UI shows no status.
  LspDocStatus? statusForPath(String path) {
    final def = languageForPath(path);
    if (def == null) return null;
    final doc = _docs[path];
    final entry = doc == null ? null : _servers[doc.serverKey];
    return LspDocStatus(
      languageId: def.id,
      label: def.label,
      running: entry?.client.isRunning ?? false,
    );
  }

  /// Restart the server serving [path].
  ///
  /// Retries startup and reopens documents with their current text even when
  /// the prior server had stopped or failed.
  Future<void> restartForPath(String path) async {
    final doc = _docs[path];
    if (doc == null) return;
    await _restartKey(doc.serverKey);
  }

  /// Restart every server for [languageId].
  ///
  /// Covers live servers and keys that retain documents after an earlier start
  /// failure, such as after the user saves a new command on the Language screen.
  Future<void> restartLanguage(String languageId) async {
    final prefix = '$languageId$_sep';
    final keys = <String>{
      ..._servers.keys.where((k) => k.startsWith(prefix)),
      ..._docs.values
          .map((d) => d.serverKey)
          .where((k) => k.startsWith(prefix)),
    };
    for (final key in keys) {
      await _restartKey(key);
    }
  }

  /// Replace the server at [key] and reopen its documents with their latest text.
  Future<void> _restartKey(String key) async {
    final entry = _servers.remove(key);
    if (entry != null) {
      entry.cancelPendingShutdown();
      await entry.sub?.cancel();
      await entry.client.kill();
      entry.client.dispose();
    }
    _statusChanges.add(null);

    final docs = <String, _DocEntry>{
      for (final e in _docs.entries)
        if (e.value.serverKey == key) e.key: e.value,
    };
    if (docs.isEmpty) return;
    final def = languageForPath(docs.keys.first);
    if (def == null) return;
    final fresh = await _ensureServer(key, def, docs.values.first.root);
    if (fresh == null || !fresh.client.isRunning) return;
    for (final e in docs.entries) {
      await fresh.client.didOpen(path: e.key, text: e.value.lastText);
    }
  }

  /// Close a document and schedule shutdown when its server has no documents.
  Future<void> closeDocument(String path) async {
    final doc = _docs.remove(path);
    if (doc == null) return;
    final entry = _servers[doc.serverKey];
    if (entry == null) return;
    if (entry.client.isRunning) await entry.client.didClose(path: path);
    final remaining = _docs.values.any((d) => d.serverKey == doc.serverKey);
    if (!remaining) _scheduleShutdown(doc.serverKey, entry);
  }

  /// Send a generic request to the server serving [path].
  ///
  /// Returns a failure when the document has no server.
  Future<Result<Object?, LspError>> requestForPath(
    String path,
    String method,
    Map<String, dynamic> params,
  ) async {
    final doc = _docs[path];
    final entry = doc == null ? null : _servers[doc.serverKey];
    if (entry == null) {
      return const Failure(LspError('No language server for this document.'));
    }
    return entry.client.request(method, params);
  }

  /// Request `textDocument/formatting` edits for a document.
  ///
  /// Returns an empty list when no server is live, formatting is unsupported,
  /// or the request fails.
  Future<List<LspTextEdit>> formatDocument(
    String path, {
    int tabSize = 2,
    bool insertSpaces = true,
  }) async {
    final result = await requestForPath(path, 'textDocument/formatting', {
      'textDocument': {'uri': Uri.file(path).toString()},
      'options': {'tabSize': tabSize, 'insertSpaces': insertSpaces},
    });
    return result.fold(parseTextEdits, (_) => const <LspTextEdit>[]);
  }

  /// Shut down all server resources during app shutdown.
  void dispose() {
    for (final entry in _servers.values) {
      entry.cancelPendingShutdown();
      entry.sub?.cancel();
      entry.client.dispose();
    }
    _servers.clear();
    _docs.clear();
    if (!_diagnostics.isClosed) _diagnostics.close();
    if (!_statusChanges.isClosed) _statusChanges.close();
  }

  void _onDiagnostics(LspDiagnosticsBatch batch) {
    if (!_diagnostics.isClosed) _diagnostics.add(batch);
  }

  void _scheduleShutdown(String key, _ServerEntry entry) {
    entry.shutdownTimer = Timer(_shutdownGrace, () async {
      // A document may have reused this server during the grace period.
      if (_docs.values.any((d) => d.serverKey == key)) return;
      _servers.remove(key);
      await entry.sub?.cancel();
      await entry.client.kill();
      entry.client.dispose();
      _statusChanges.add(null);
      debugPrint('[lsp-pool] shut down $key');
    });
  }

  /// Resolve a server specification and executable.
  ///
  /// Applies the Wave 2 user override or the default, then locates the binary
  /// because GUI apps do not inherit the shell PATH.
  Future<LspServerSpec?> _resolveSpec(LanguageDef def) async {
    String executable = def.defaultExecutable;
    List<String> args = def.defaultArgs;

    final override = commandOverrides[def.id]?.trim();
    if (override != null && override.isNotEmpty) {
      final parts = splitLspCommand(override);
      if (parts.isNotEmpty) {
        executable = parts.first;
        args = parts.sublist(1);
      }
    }

    final resolved = await resolveExecutable(executable);
    // Do not start a server unless the binary exists. `resolveExecutable`
    // returns the raw name when it cannot resolve it, for example `gopls` when
    // `~/go/bin` is absent from a GUI app's PATH. Spawning a missing executable
    // raises ProcessException and, in merged-thread mode, previously triggered
    // SIGPIPE that terminated the whole app. Degrade gracefully to null and a
    // stopped status; restart retries after installation or command changes.
    if (!_resolvesToRealFile(resolved)) return null;
    return def.toSpec(executable: resolved, args: args);
  }

  /// Check whether [exec] resolves to an existing absolute file.
  ///
  /// A raw name without a path separator means `resolveExecutable` did not find
  /// the executable, so the server cannot start.
  bool _resolvesToRealFile(String exec) =>
      (exec.contains('/') || exec.contains(r'\')) && File(exec).existsSync();

  /// Separate the `(language, root)` key with NUL.
  ///
  /// NUL cannot appear in a path or language id, so it remains unambiguous even
  /// when roots contain spaces.
  static const String _sep = '\u0000';

  String _key(String languageId, String root) => '$languageId$_sep$root';
}

class _ServerEntry {
  _ServerEntry(this.client);

  final LspClient client;
  StreamSubscription<LspDiagnosticsBatch>? sub;
  Timer? shutdownTimer;

  void cancelPendingShutdown() {
    shutdownTimer?.cancel();
    shutdownTimer = null;
  }
}

class _DocEntry {
  _DocEntry(this.serverKey, this.root, this.lastText);

  final String serverKey;

  /// Root retained from open and reused to recreate the same server on restart.
  final String root;

  /// Latest text from open/change, used to reopen the document after restart.
  String lastText;

  int version = 1;
}

/// Describe a document's LSP state for the Files pane status bar.
class LspDocStatus {
  const LspDocStatus({
    required this.languageId,
    required this.label,
    required this.running,
  });

  final String languageId;
  final String label;
  final bool running;
}
