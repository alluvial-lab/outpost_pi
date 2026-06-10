import 'dart:io';

/// Configuração de como o Cockpit spawna o `pi --mode rpc`.
///
/// **Revisita a decisão B (plano 37)** — o plano precisa registrar as duas
/// mudanças abaixo (tarefa do orquestrador; o agente cockpit só edita `cockpit/`):
/// - `noSession = false`: o pi **persiste** a sessão em
///   `~/.pi/agent/sessions/<cwd>/`, e o Cockpit reanexa via `switch_session`.
/// - `noExtensions = false`: o pi **carrega as extensions** do usuário — sem
///   isso `get_commands` vem vazio (todo slash command vem de extension). A
///   malha/relay **não** inicia sozinha; só se você invocar `/remote-pi`.
///
/// Provider/model e o path do binário são resolvidos no boot e podem ser
/// sobrescritos por `--dart-define` (compile-time):
///
/// ```bash
/// flutter run -d macos \
///   --dart-define=COCKPIT_PI_PROVIDER=deepseek \
///   --dart-define=COCKPIT_PI_MODEL=deepseek-chat
/// ```
///
/// Sem overrides, o pi usa o provider/model padrão do `~/.pi/agent/settings.json`.
class PiSpawnConfig {
  const PiSpawnConfig({
    required this.executable,
    this.provider,
    this.model,
    this.noSession = false,
    this.noExtensions = false,
  });

  /// Caminho absoluto (ou nome no PATH) do binário `pi`.
  final String executable;

  /// `--provider` (vazio = usa o default do pi).
  final String? provider;

  /// `--model` (vazio = usa o default do pi).
  final String? model;

  /// `--no-session` — quando `true`, não persiste a sessão. Padrão `false`:
  /// deixamos o pi gravar a sessão pra poder restaurá-la depois.
  final bool noSession;

  /// `--no-extensions` — quando `true`, não carrega extensions. Padrão `false`:
  /// carregamos as extensions pra ter os slash commands (`get_commands`).
  final bool noExtensions;

  /// [sessionId] é o ID (basename sem `.jsonl`) da sessão a restaurar. Quando
  /// presente, o pi inicia já carregado naquela sessão — evita o ciclo extra de
  /// `switch_session` que causa re-avaliação dupla do módulo da extensão.
  List<String> spawnArgs({String? sessionId}) => <String>[
    '--mode', 'rpc',
    if (sessionId != null) ...['--session', sessionId],
    if (noSession) '--no-session',
    if (noExtensions) '--no-extensions',
    if (provider != null && provider!.isNotEmpty) ...['--provider', provider!],
    if (model != null && model!.isNotEmpty) ...['--model', model!],
  ];

  /// Resolve a config no boot. Lê os `--dart-define` e localiza o binário.
  static Future<PiSpawnConfig> resolve() async {
    const provider = String.fromEnvironment('COCKPIT_PI_PROVIDER');
    const model = String.fromEnvironment('COCKPIT_PI_MODEL');
    const pathOverride = String.fromEnvironment('COCKPIT_PI_PATH');

    return PiSpawnConfig(
      executable: await _resolveExecutable(pathOverride),
      provider: provider.isEmpty ? null : provider,
      model: model.isEmpty ? null : model,
    );
  }

  /// App macOS não herda o PATH do shell, então procuramos o binário em
  /// caminhos conhecidos. Override explícito vence; 'pi' (PATH) é o último recurso.
  static Future<String> _resolveExecutable(String override) async {
    if (override.isNotEmpty) return override;

    if (Platform.isWindows) {
      // No Windows o `pi` costuma ser um shim do npm (`pi.cmd`/`pi.ps1`/`pi.exe`)
      // em `%APPDATA%\npm` ou onde o PATH apontar. Varre o PATH manualmente.
      final fromPath = await _searchWindowsPath('pi');
      if (fromPath != null) return fromPath;
      final appData = Platform.environment['APPDATA'];
      if (appData != null) {
        for (final ext in const ['cmd', 'exe', 'bat']) {
          final shim = '$appData\\npm\\pi.$ext';
          if (await File(shim).exists()) return shim;
        }
      }
      return 'pi';
    }

    const candidates = <String>[
      '/opt/homebrew/bin/pi',
      '/usr/local/bin/pi',
    ];
    for (final candidate in candidates) {
      if (await File(candidate).exists()) return candidate;
    }
    final home = Platform.environment['HOME'];
    if (home != null) {
      final local = '$home/.local/bin/pi';
      if (await File(local).exists()) return local;
    }
    return 'pi';
  }

  /// Varre cada diretório do `PATH` testando `name` + cada extensão do `PATHEXT`
  /// (`.COM;.EXE;.BAT;.CMD;…`). Devolve o caminho absoluto do primeiro hit, ou
  /// `null`. Específico de Windows.
  static Future<String?> _searchWindowsPath(String name) async {
    final pathEnv = Platform.environment['PATH'] ?? '';
    final pathExt = (Platform.environment['PATHEXT'] ?? '.COM;.EXE;.BAT;.CMD')
        .split(';')
        .where((e) => e.isNotEmpty)
        .toList();
    for (final dir in pathEnv.split(';')) {
      if (dir.isEmpty) continue;
      for (final ext in pathExt) {
        final candidate = '$dir\\$name$ext';
        if (await File(candidate).exists()) return candidate;
      }
    }
    return null;
  }
}
