import 'dart:convert';
import 'dart:io';

import 'package:cockpit/domain/contracts/remote_pi_config_store.dart';
import 'package:cockpit/domain/entities/remote_pi_config.dart';

/// Lê/escreve nos mesmos arquivos do remote-pi:
/// - local: `<cwd>/.pi/remote-pi/config.json` → `{agent_name, auto_start_relay,
///   session_name}`
/// - relay global: `~/.pi/remote/config.json` → `{relay}`
///
/// Na escrita, faz **merge** com o conteúdo existente (preserva chaves que não
/// gerenciamos), igual ao que a extensão faz.
class RemotePiConfigStoreImpl implements RemotePiConfigStore {
  const RemotePiConfigStoreImpl();

  String _localPath(String cwd) => '$cwd/.pi/remote-pi/config.json';

  String _relayPath() {
    final home = Platform.environment['HOME'] ?? '';
    return '$home/.pi/remote/config.json';
  }

  @override
  Future<RemotePiConfig> load(String cwd) async {
    final local = await _readJson(_localPath(cwd));
    final relay = await _readJson(_relayPath());
    return RemotePiConfig(
      agentName: local['agent_name'] as String?,
      workspace: local['workspace'] as String?,
      autoStartRelay: local['auto_start_relay'] == true,
      sessionName: local['session_name'] as String?,
      relayUrl: relay['relay'] as String?,
    );
  }

  @override
  Future<RemotePiConfig> ensureDefaults(
    String cwd, {
    required String workspace,
  }) async {
    final file = File(_localPath(cwd));
    if (!await file.exists()) {
      await _writeJson(file, <String, dynamic>{
        'agent_name': _basename(cwd),
        'workspace': workspace,
        'auto_start_relay': false,
      });
    }
    return load(cwd);
  }

  String _basename(String path) {
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    return parts.isEmpty ? path : parts.last;
  }

  @override
  Future<void> save(String cwd, RemotePiConfig config) async {
    // Só o nome do agente é editável aqui — o relay é **só visualização**, então
    // não escrevemos auto_start_relay nem a URL do relay (isso fica pro
    // `/remote-pi setup` da extensão). O merge preserva todas as outras chaves.
    final localFile = File(_localPath(cwd));
    final local = await _readJson(localFile.path);
    if (config.agentName != null && config.agentName!.isNotEmpty) {
      local['agent_name'] = config.agentName;
    }
    await _writeJson(localFile, local);
  }

  Future<Map<String, dynamic>> _readJson(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return <String, dynamic>{};
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> _writeJson(File file, Map<String, dynamic> data) async {
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString('${encoder.convert(data)}\n');
  }
}
