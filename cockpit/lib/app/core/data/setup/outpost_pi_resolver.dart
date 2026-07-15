import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/core/utils/executable_resolver.dart';

/// Resolve outpost-pi commands for the supervisor installer and relay adapters.
///
/// On POSIX, `outpost-pi` is a binary on PATH or in known prefixes. On Windows,
/// it is not on PATH; invoke the extension as `node <dist/index.js>`, resolving
/// it from `packages[]` in `~/.pi/agent/settings.json`.

/// Resolve the user's home directory, using USERPROFILE on Windows.
String? outpostPiHome() =>
    Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];

/// Resolve the absolute path to the outpost-pi extension's `dist/index.js`.
///
/// Reads `packages[]` from `~/.pi/agent/settings.json` and returns `null` when
/// the extension cannot be located.
Future<String?> resolveOutpostPiIndexJs() async {
  final home = outpostPiHome();
  if (home == null) return null;
  try {
    final file = File('$home/.pi/agent/settings.json');
    if (!await file.exists()) return null;
    final json = jsonDecode(await file.readAsString());
    if (json is! Map) return null;
    final packages = json['packages'];
    if (packages is! List) return null;

    final spec = packages.whereType<String>().firstWhere((p) {
      final low = p.toLowerCase();
      return low.contains('outpost-pi') || low.endsWith('pi-extension');
    }, orElse: () => '');
    if (spec.isEmpty) return null;

    final String pkgRoot;
    if (!spec.contains('/') && !spec.contains(r'\')) {
      // npm specs (`npm:outpost-pi` / `outpost-pi`) use pi's node_modules.
      pkgRoot = '$home/.pi/agent/npm/node_modules/outpost-pi';
    } else {
      // Local paths may be relative to ~/.pi/agent/ and contain `../`.
      final clean = spec.startsWith('npm:') ? spec.substring(4) : spec;
      pkgRoot = Uri.directory('$home/.pi/agent/').resolve(clean).toFilePath();
    }

    final indexJs = File('$pkgRoot/dist/index.js');
    if (await indexJs.exists()) return indexJs.path;
    return null;
  } catch (_) {
    return null;
  }
}

/// Resolve `node` from known paths using the same strategy as pi.
Future<String> resolveNode() => resolveExecutable(
  'node',
  unixCandidates: const ['/opt/homebrew/bin/node', '/usr/local/bin/node'],
  unixHomeRelative: const ['.local/bin/node'],
  windowsExtraDirs: const [r'C:\Program Files\nodejs'],
);

/// Resolve the directory containing `node`.
///
/// This is usually the same bin directory as `pi`, `npm`, and `outpost-pi`.
/// Returns `null` when node did not resolve to a path.
Future<String?> resolveNodeBinDir() async {
  final node = await resolveNode();
  final idx = node.lastIndexOf(RegExp(r'[/\\]'));
  return idx > 0 ? node.substring(0, idx) : null;
}

/// Build a process environment with the `node` bin directory prepended to PATH.
///
/// The `pi` and `outpost-pi` shims use `#!/usr/bin/env node`, but nvm/Homebrew
/// installs may not appear on the PATH inherited by a GUI app, causing
/// `/usr/bin/env: 'node': No such file or directory`.
Future<Map<String, String>> envWithNodeOnPath() async {
  final env = Map<String, String>.of(Platform.environment);
  final dir = await resolveNodeBinDir();
  if (dir != null) {
    final sep = Platform.isWindows ? ';' : ':';
    // Windows commonly uses `Path`; POSIX uses `PATH`.
    final key = env.containsKey('Path') && !env.containsKey('PATH')
        ? 'Path'
        : 'PATH';
    final cur = env[key] ?? '';
    if (!cur.split(sep).contains(dir)) {
      env[key] = cur.isEmpty ? dir : '$dir$sep$cur';
    }
  }
  return env;
}

/// Resolve the executable and prefix arguments used to invoke outpost-pi.
///
/// POSIX uses the `outpost-pi` binary with no prefix arguments; Windows uses
/// `node <index.js>`. Returns `null` on Windows when the extension's `index.js`
/// cannot be located.
Future<({String exe, List<String> prefixArgs})?>
resolveOutpostPiCommand() async {
  if (Platform.isWindows) {
    final indexJs = await resolveOutpostPiIndexJs();
    if (indexJs == null) return null;
    final node = await resolveNode();
    return (exe: node, prefixArgs: <String>[indexJs]);
  }
  final exe = await resolveExecutable(
    'outpost-pi',
    unixCandidates: const [
      '/opt/homebrew/bin/outpost-pi',
      '/usr/local/bin/outpost-pi',
    ],
    unixHomeRelative: const ['.local/bin/outpost-pi'],
  );
  return (exe: exe, prefixArgs: const <String>[]);
}
