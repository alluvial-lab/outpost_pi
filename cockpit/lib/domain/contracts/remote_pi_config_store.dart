import 'package:cockpit/domain/entities/remote_pi_config.dart';

/// Lê/escreve a config do remote-pi nos **mesmos arquivos e formato** que o
/// `/remote-pi setup` usa (local por pasta + relay global). Contrato no domínio;
/// impl (dart:io) em `data/`.
///
/// Nota: o cockpit continua spawnando `pi --mode rpc` **puro** — esta config é
/// persistida para uso futuro (reachability via relay), não ativa o relay agora.
abstract class RemotePiConfigStore {
  Future<RemotePiConfig> load(String cwd);
  Future<void> save(String cwd, RemotePiConfig config);

  /// Cria `<cwd>/.pi/remote-pi/config.json` com valores padrão se ainda não
  /// existir (não sobrescreve): `agent_name` = nome da pasta, `auto_start_relay`
  /// = false, e `workspace` = [workspace] (o nome do projeto ao qual o agente
  /// pertence).
  Future<RemotePiConfig> ensureDefaults(String cwd, {required String workspace});
}
