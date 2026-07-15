import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/core/data/setup/outpost_pi_resolver.dart';
import 'package:cockpit/app/settings/domain/contracts/relay_gateway.dart';
import 'package:cockpit/app/settings/domain/entities/paired_device.dart';
import 'package:cockpit/app/core/domain/exceptions/relay_error.dart';
import 'package:cockpit/app/core/domain/result.dart';

/// Adapt [RelayGateway] by shelling out to `outpost-pi` and reading the global
/// `~/.pi/remote/config.json` file.
///
/// [resolveOutpostPiCommand] locates `outpost-pi` as a binary on PATH or under
/// known POSIX prefixes, and as `node <index.js>` on Windows where it is not on
/// PATH. Resolution is memoized so filesystem existence checks run only once.
class RelayGatewayImpl implements RelayGateway {
  RelayGatewayImpl();

  Future<({String exe, List<String> prefixArgs})?>? _resolvedCmd;

  // Windows does not set HOME; its equivalent is USERPROFILE.
  String? get _home => outpostPiHome();

  @override
  Future<Result<String?, RelayError>> currentRelay() async {
    final home = _home;
    if (home == null) {
      return const Failure(RelayError('HOME not found in the environment.'));
    }
    try {
      final file = File('$home/.pi/remote/config.json');
      if (!await file.exists()) return const Success(null);
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return const Success(null);
      final relay = json['relay'];
      return Success(relay is String && relay.isNotEmpty ? relay : null);
    } catch (e, s) {
      return Failure(
        RelayError(
          'Failed to read the configured relay.',
          cause: e,
          stackTrace: s,
        ),
      );
    }
  }

  @override
  Future<Result<void, RelayError>> setRelay(String url) =>
      _run(<String>['set-relay', url], 'Failed to set the relay.');

  @override
  Future<Result<List<PairedDevice>, RelayError>> listDevices() async {
    // Read peers directly from `~/.pi/remote/peers.json`, the same source used
    // by `/outpost-pi`. The CLI has no `outpost-pi devices` subcommand, and
    // reading the file works consistently across macOS, Linux, and Windows.
    final home = _home;
    if (home == null) {
      return const Failure(RelayError('HOME not found in the environment.'));
    }
    try {
      final file = File('$home/.pi/remote/peers.json');
      if (!await file.exists()) return const Success(<PairedDevice>[]);
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return const Success(<PairedDevice>[]);
      final peers = json['peers'];
      if (peers is! List) return const Success(<PairedDevice>[]);

      final devices = <PairedDevice>[];
      for (final p in peers.whereType<Map>()) {
        final epk = p['remote_epk'];
        if (epk is! String || epk.isEmpty) continue;
        final name = p['name'];
        // shortId is remote_epk, which `/outpost-pi revoke <epk>` accepts;
        // label is the human-readable pairing name, such as "iPhone".
        devices.add(
          PairedDevice(
            shortId: epk,
            label: name is String && name.isNotEmpty ? name : epk,
          ),
        );
      }
      return Success(devices);
    } catch (e, s) {
      return Failure(
        RelayError('Failed to list paired devices.', cause: e, stackTrace: s),
      );
    }
  }

  @override
  Future<Result<void, RelayError>> checkHealth(String url) async {
    final base = url.trim().replaceAll(RegExp(r'/+$'), '');
    final parsed = Uri.tryParse(base);
    if (parsed == null ||
        (parsed.scheme != 'http' && parsed.scheme != 'https') ||
        parsed.host.isEmpty) {
      return const Failure(
        RelayError('Invalid URL — use http:// or https://.'),
      );
    }

    const timeout = Duration(seconds: 8);
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .getUrl(Uri.parse('$base/health'))
          .timeout(timeout);
      final response = await request.close().timeout(timeout);
      await response.drain<void>();
      if (response.statusCode == 200) return const Success(null);
      return Failure(
        RelayError('The relay responded HTTP ${response.statusCode}.'),
      );
    } on TimeoutException {
      return const Failure(RelayError('Timed out contacting the relay.'));
    } on SocketException {
      return const Failure(
        RelayError('Could not connect to the relay (host/port).'),
      );
    } on HandshakeException {
      return const Failure(RelayError('TLS failure contacting the relay.'));
    } catch (error) {
      return Failure(RelayError('Failed to contact the relay: $error'));
    } finally {
      client.close(force: true);
    }
  }

  // ---- internals ------------------------------------------------------------

  /// Run the command and discard its output, retaining only `exitCode`.
  Future<Result<void, RelayError>> _run(
    List<String> args,
    String onError,
  ) async {
    final captured = await _capture(args, onError);
    return captured.fold((_) => const Success(null), (error) => Failure(error));
  }

  /// Run the command and return trimmed stdout on success.
  ///
  /// Maps spawn failures and nonzero `exitCode` values to [RelayError], using
  /// the stderr message when available.
  Future<Result<String, RelayError>> _capture(
    List<String> args,
    String onError,
  ) async {
    try {
      final cmd = await _cmd();
      if (cmd == null) {
        return Failure(
          RelayError(
            '$onError\nCould not find outpost-pi (install the extension).',
          ),
        );
      }
      final result = await Process.run(
        cmd.exe,
        [...cmd.prefixArgs, ...args],
        runInShell: Platform.isWindows,
        environment: await envWithNodeOnPath(),
      );
      if (result.exitCode != 0) {
        final err = (result.stderr as String? ?? '').trim();
        return Failure(RelayError(err.isEmpty ? onError : '$onError\n$err'));
      }
      return Success((result.stdout as String? ?? '').trim());
    } catch (e, s) {
      return Failure(RelayError(onError, cause: e, stackTrace: s));
    }
  }

  Future<({String exe, List<String> prefixArgs})?> _cmd() =>
      _resolvedCmd ??= resolveOutpostPiCommand();
}
