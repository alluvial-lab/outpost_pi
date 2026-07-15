import 'package:cockpit/app/core/utils/executable_resolver.dart';

/// Configure how Cockpit spawns `pi --mode rpc`.
///
/// `noSession = false` lets Pi persist sessions under
/// `~/.pi/agent/sessions/<cwd>/` so Cockpit can reattach with `switch_session`.
/// `noExtensions = false` loads user extensions so `get_commands` includes
/// slash commands. Loading extensions does not itself start the mesh or relay;
/// invoking `/outpost-pi` does.
///
/// Provider, model, and executable path are resolved at boot and may be
/// overridden at compile time with `--dart-define`:
///
/// ```bash
/// flutter run -d macos \
///   --dart-define=COCKPIT_PI_PROVIDER=deepseek \
///   --dart-define=COCKPIT_PI_MODEL=deepseek-chat
/// ```
///
/// Without overrides, Pi uses the default provider and model from
/// `~/.pi/agent/settings.json`.
class PiSpawnConfig {
  const PiSpawnConfig({
    required this.executable,
    this.provider,
    this.model,
    this.noSession = false,
    this.noExtensions = false,
  });

  /// Absolute path, or `PATH`-resolvable name, of the `pi` binary.
  final String executable;

  /// `--provider` override; empty uses Pi's default.
  final String? provider;

  /// `--model` override; empty uses Pi's default.
  final String? model;

  /// Whether to pass `--no-session` and disable session persistence.
  ///
  /// Defaults to `false` so Cockpit can restore persisted sessions.
  final bool noSession;

  /// Whether to pass `--no-extensions` and suppress user extensions.
  ///
  /// Defaults to `false` so `get_commands` includes extension slash commands.
  final bool noExtensions;

  /// Build RPC arguments, optionally restoring [sessionId].
  ///
  /// [sessionId] is the session basename without `.jsonl`. Passing it at spawn
  /// avoids an extra `switch_session` cycle and duplicate extension evaluation.
  List<String> spawnArgs({String? sessionId}) => <String>[
    '--mode',
    'rpc',
    if (sessionId != null) ...['--session', sessionId],
    if (noSession) '--no-session',
    if (noExtensions) '--no-extensions',
    if (provider != null && provider!.isNotEmpty) ...['--provider', provider!],
    if (model != null && model!.isNotEmpty) ...['--model', model!],
  ];

  /// Resolve compile-time overrides and locate the Pi binary during startup.
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

  /// Resolve the Pi executable for a macOS GUI that does not inherit shell `PATH`.
  ///
  /// An explicit override wins; the bare `pi` name is the final fallback.
  static Future<String> _resolveExecutable(String override) async {
    if (override.isNotEmpty) return override;
    return resolveExecutable(
      'pi',
      unixCandidates: const ['/opt/homebrew/bin/pi', '/usr/local/bin/pi'],
      unixHomeRelative: const ['.local/bin/pi'],
    );
  }
}
