import 'package:cockpit/app/core/domain/contracts/service.dart';
import 'package:cockpit/app/cockpit/domain/entities/agent_snapshot.dart';
import 'package:cockpit/app/cockpit/domain/entities/context_usage.dart';
import 'package:cockpit/app/cockpit/domain/entities/pi_command.dart';
import 'package:cockpit/app/cockpit/domain/entities/pi_model.dart';
import 'package:cockpit/app/cockpit/domain/entities/prompt_image.dart';
import 'package:cockpit/app/cockpit/domain/entities/rpc_event.dart';
import 'package:cockpit/app/cockpit/domain/entities/thinking_level.dart';
import 'package:cockpit/app/cockpit/domain/entities/transcript_event.dart';
import 'package:cockpit/app/cockpit/domain/exceptions/rpc_error.dart';
import 'package:cockpit/app/core/domain/result.dart';

/// Hide the low-level `Process.start` boundary for `pi --mode rpc`.
///
/// Declared in the domain and implemented in `data/rpc/`, this interface keeps
/// `dart:io`, stdin/stdout, and JSON outside the domain.
///
/// The plan 37 MVP owns one process per gateway and defers multiplexing across
/// multiple panes. The broadcast [events] stream lives for the gateway's full
/// lifetime and survives successive [spawn] and [kill] calls.
abstract class RpcProcessGateway implements Service {
  /// Emit typed events from the agent's stdout as a broadcast stream.
  ///
  /// The `ui/` may subscribe again between spawns without losing the controller.
  Stream<RpcEvent> get events;

  /// Report whether this session currently has a live agent.
  bool get isRunning;

  /// Return the current agent's child-process working directory, or `null`.
  String? get workingDirectory;

  /// Start a plain `pi --mode rpc` process in [workingDirectory].
  ///
  /// Returns a failure when an agent is already live. In the single-pane MVP,
  /// callers own deduplication.
  ///
  /// [environment] is **merged** with the parent process environment, so absent
  /// variables are inherited normally. Use it to inject
  /// `OUTPOST_PI_DIRECT_CONFIG` without losing PATH, HOME, or other variables.
  ///
  /// [sessionId] optionally identifies the session to restore: the `.jsonl`
  /// basename without its extension. When present, the process receives
  /// `--session <id>` and starts with that session loaded, without a later
  /// `switch_session` command.
  Future<Result<void, RpcError>> spawn({
    required String workingDirectory,
    Map<String, String>? environment,
    String? sessionId,
  });

  /// Send a user prompt over stdin.
  ///
  /// When [steerIfBusy] is `true`, attach `streamingBehavior: "steer"` to queue
  /// it during streaming. [images] become the command's `images` field for
  /// vision attachments.
  Future<Result<void, RpcError>> sendPrompt(
    String message, {
    bool steerIfBusy = false,
    List<PromptImage> images = const <PromptImage>[],
  });

  /// Respond to an interactive `extension_ui_request` for select, confirm,
  /// input, or editor UI.
  ///
  /// Writes `{type:"extension_ui_response", id, ...response}` to stdin.
  /// [response] is `{value:…}`, `{confirmed:…}`, or `{cancelled:true}`.
  Future<Result<void, RpcError>> respondUi(
    String id,
    Map<String, dynamic> response,
  );

  /// Stop the child process cleanly without leaving an orphan.
  ///
  /// Close stdin first for a graceful code-0 exit, escalating to
  /// SIGTERM/SIGKILL only if the process does not exit.
  Future<void> kill();

  // --- Request/response commands correlated by `id` -------------------------

  /// Run `get_available_models` to return the configured model catalog.
  Future<Result<List<PiModel>, RpcError>> availableModels();

  /// Run `get_commands` to return slash commands supplied by extensions.
  Future<Result<List<PiCommand>, RpcError>> commands();

  /// Run `get_state` to return the current model, effort, and streaming state.
  Future<Result<AgentSnapshot, RpcError>> state();

  /// Run `set_model` and return the model that was applied.
  Future<Result<PiModel, RpcError>> setModel(PiModel model);

  /// Run `set_thinking_level` to adjust reasoning effort.
  Future<Result<void, RpcError>> setThinkingLevel(ThinkingLevel level);

  /// Run `abort` to interrupt the current turn **without** killing the process.
  Future<Result<void, RpcError>> abort();

  /// Run `new_session` to start a fresh session with an empty conversation.
  Future<Result<void, RpcError>> newSession();

  /// Run `compact` to compact the current session's context.
  Future<Result<void, RpcError>> compact();

  /// Run `switch_session` to load a saved Pi session by path.
  Future<Result<void, RpcError>> switchSession(String sessionPath);

  /// Run `get_messages` to return current-session transcript events ready for
  /// replay through the shared reducer.
  Future<Result<List<CockpitTranscriptEvent>, RpcError>> getMessages({
    required String sessionId,
  });

  /// Run `get_session_stats` to return context-window usage, which may be `null`.
  Future<Result<ContextUsage?, RpcError>> sessionStats();

  /// Send an Outpost-Pi overlay command directly over stdin.
  ///
  /// This bypasses the LLM and does not appear in the transcript. The domain
  /// supplies a value aligned with the `cockpit-control` schema while the
  /// adapter owns transport serialization. Responses arrive on stdout as
  /// custom `outpost-pi:*` events.
  Future<Result<void, RpcError>> sendControl(PiControlCommand command);
}
