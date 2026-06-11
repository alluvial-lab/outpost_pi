import 'dart:convert';
import 'dart:io';

import 'package:cockpit/config/utils/executable_resolver.dart';

/// Helpers de resolução do `remote-pi` — compartilhados entre o instalador do
/// supervisor e o gateway de relay/pareamento.
///
/// No POSIX o `remote-pi` é um binário no PATH/prefixos conhecidos. No Windows
/// **não** está no PATH: invocamos `node <dist/index.js>` da extensão, resolvido
/// a partir do `packages[]` em `~/.pi/agent/settings.json`.

/// `~/` do usuário: Windows não seta `HOME`, o equivalente é `USERPROFILE`.
String? remotePiHome() =>
    Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];

/// Caminho absoluto do `dist/index.js` da extensão remote-pi (via `packages[]`
/// do `~/.pi/agent/settings.json`), ou `null` se não der pra achar.
Future<String?> resolveRemotePiIndexJs() async {
  final home = remotePiHome();
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
      return low.contains('remote-pi') || low.endsWith('pi-extension');
    }, orElse: () => '');
    if (spec.isEmpty) return null;

    final String pkgRoot;
    if (!spec.contains('/') && !spec.contains(r'\')) {
      // Spec do npm (`npm:remote-pi` / `remote-pi`) → node_modules do pi.
      pkgRoot = '$home/.pi/agent/npm/node_modules/remote-pi';
    } else {
      // Caminho local (possivelmente relativo a ~/.pi/agent/, com `../`).
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

/// Resolve o `node` em caminhos conhecidos (mesma estratégia do `pi`).
Future<String> resolveNode() => resolveExecutable(
  'node',
  unixCandidates: const ['/opt/homebrew/bin/node', '/usr/local/bin/node'],
  unixHomeRelative: const ['.local/bin/node'],
  windowsExtraDirs: const [r'C:\Program Files\nodejs'],
);

/// Como invocar o `remote-pi`: o executável + os args de prefixo. No POSIX é o
/// binário `remote-pi` (prefixo vazio); no Windows é `node <index.js>`. Devolve
/// `null` se o Windows não conseguir localizar o `index.js` da extensão.
Future<({String exe, List<String> prefixArgs})?> resolveRemotePiCommand() async {
  if (Platform.isWindows) {
    final indexJs = await resolveRemotePiIndexJs();
    if (indexJs == null) return null;
    final node = await resolveNode();
    return (exe: node, prefixArgs: <String>[indexJs]);
  }
  final exe = await resolveExecutable(
    'remote-pi',
    unixCandidates: const ['/opt/homebrew/bin/remote-pi', '/usr/local/bin/remote-pi'],
    unixHomeRelative: const ['.local/bin/remote-pi'],
  );
  return (exe: exe, prefixArgs: const <String>[]);
}
