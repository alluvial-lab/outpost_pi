/// Config do remote-pi, espelhando os arquivos que o `/remote-pi setup` escreve:
/// - local (por pasta): `<cwd>/.pi/remote-pi/config.json` → agent_name,
///   auto_start_relay, session_name
/// - relay global: `~/.pi/remote/config.json` → relay
class RemotePiConfig {
  const RemotePiConfig({
    this.agentName,
    this.workspace,
    this.autoStartRelay = false,
    this.sessionName,
    this.relayUrl,
  });

  final String? agentName;

  /// Nome do "workspace" (pasta pai) quando o pai tem AGENTS.md/CLAUDE.md;
  /// vazio caso contrário. Campo próprio do cockpit no mesmo arquivo.
  final String? workspace;

  final bool autoStartRelay;
  final String? sessionName;

  /// URL do relay (config global, read-only aqui por enquanto).
  final String? relayUrl;

  RemotePiConfig copyWith({
    String? agentName,
    String? workspace,
    bool? autoStartRelay,
    String? sessionName,
    String? relayUrl,
  }) {
    return RemotePiConfig(
      agentName: agentName ?? this.agentName,
      workspace: workspace ?? this.workspace,
      autoStartRelay: autoStartRelay ?? this.autoStartRelay,
      sessionName: sessionName ?? this.sessionName,
      relayUrl: relayUrl ?? this.relayUrl,
    );
  }
}
