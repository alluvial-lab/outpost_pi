import 'package:cockpit/app/core/domain/entities/lsp_diagnostic.dart';
import 'package:cockpit/app/core/domain/exceptions/lsp_error.dart';
import 'package:cockpit/app/core/domain/result.dart';

/// Describe how to launch a language server and identify its LSP language.
///
/// `lsp_launchers.dart` produces one specification per language; callers can
/// also construct a specification directly for a custom server.
class LspServerSpec {
  const LspServerSpec({
    required this.languageId,
    required this.executable,
    this.args = const <String>[],
  });

  /// LSP language identifier sent in `didOpen`, such as `dart` or `typescript`.
  final String languageId;

  /// Server binary path or name, resolved on `PATH` before spawning.
  final String executable;

  /// Fixed server arguments, such as `language-server` or `--stdio`.
  final List<String> args;
}

/// Control one language-server process for one project root.
///
/// Communicates over stdin/stdout using JSON-RPC 2.0 with `Content-Length`
/// framing. `LspServerPool` creates, reuses, and disposes clients by language
/// and project root; this contract defines the lower-level process boundary.
abstract class LspClient {
  /// Broadcast diagnostics published by the server, one batch per document.
  Stream<LspDiagnosticsBatch> get diagnostics;

  bool get isRunning;

  /// Absolute project root served by this process.
  String get rootPath;

  /// Spawn the process and perform the `initialize` → `initialized` handshake.
  Future<Result<void, LspError>> start();

  /// Send `textDocument/didOpen`, converting absolute [path] to a `file://` URI.
  Future<void> didOpen({required String path, required String text});

  /// Send a full-sync `textDocument/didChange` with a monotonically increasing [version].
  Future<void> didChange({
    required String path,
    required String text,
    required int version,
  });

  /// `textDocument/didClose`.
  Future<void> didClose({required String path});

  /// Send a generic JSON-RPC request such as `textDocument/formatting`.
  ///
  /// Returns a failure when the request times out or the server reports an error.
  Future<Result<Object?, LspError>> request(
    String method,
    Map<String, dynamic> params,
  );

  /// Shut down gracefully, escalating from LSP exit to process termination.
  Future<void> kill();

  /// Synchronously stop the process during app shutdown to prevent an orphan.
  void dispose();
}

/// Create [LspClient] instances through a named, injectable factory.
///
/// The named contract supports the project's `.new` injection rule, which
/// cannot reliably parse `X Function()` dependencies.
abstract class LspClientFactory {
  /// Create a fresh client for one server specification and project root.
  ///
  /// The caller owns the returned client's start, kill, and dispose lifecycle.
  LspClient create({required LspServerSpec spec, required String rootPath});
}
