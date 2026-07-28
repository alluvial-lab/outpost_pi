import 'dart:async';
import 'dart:convert';

import 'package:cockpit/app/cockpit/domain/contracts/rpc_gateway_factory.dart';
import 'package:cockpit/app/cockpit/domain/entities/agent_session_projection.dart';
import 'package:cockpit/app/cockpit/domain/entities/agent_session_signal.dart';
import 'package:cockpit/app/cockpit/domain/entities/agent_turn_projection.dart';
import 'package:cockpit/app/cockpit/domain/entities/context_usage.dart';
import 'package:cockpit/app/cockpit/domain/entities/pi_command.dart';
import 'package:cockpit/app/cockpit/domain/entities/pi_model.dart';
import 'package:cockpit/app/cockpit/domain/entities/prompt_image.dart';
import 'package:cockpit/app/cockpit/domain/entities/rpc_event.dart';
import 'package:cockpit/app/cockpit/domain/entities/rpc_ui_response.dart';
import 'package:cockpit/app/cockpit/domain/entities/thinking_level.dart';
import 'package:cockpit/app/cockpit/domain/entities/transcript_event.dart';
import 'package:cockpit/app/cockpit/domain/entities/transcript_message.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_tab.dart';
import 'package:cockpit/app/cockpit/ui/session/agent_entry.dart';
import 'package:cockpit/app/cockpit/ui/session/agent_process_controller.dart';
import 'package:cockpit/app/cockpit/ui/session/pane_item.dart';
import 'package:flutter/foundation.dart';

/// Preserve the legacy lifecycle labels consumed by existing agent-tab widgets.
enum AgentStatus { empty, booting, idle, crashed }

/// Own one agent tab, its RPC process, transcript, and interactive controls.
///
/// Each pane listens only to its own [AgentSession], so streaming updates
/// rebuild that pane rather than the whole workspace. The session delegates
/// process effects to [AgentProcessController] and projects them for the UI.
class AgentSession extends PaneItem {
  AgentSession({
    required this.id,
    required this.projectId,
    required this.workingDirectory,
    required RpcGatewayFactory factory,
    String? title,
    this.autoStartRelay = false,
    this.isPlaceholder = false,
  }) : _process = AgentProcessController(factory: factory),
       _title = title ?? 'New agent' {
    _signalSub = _process.signals.listen(_onSignal);
  }

  /// Restore an agent session from a persisted agent-tab descriptor.
  ///
  /// Throws [ArgumentError] when [tab] is not an agent descriptor.
  factory AgentSession.fromWorkspaceTab({
    required WorkspaceTab tab,
    required String projectId,
    required String workingDirectory,
    required RpcGatewayFactory factory,
  }) {
    if (tab.kind != WorkspaceTabKind.agent) {
      throw ArgumentError.value(tab.kind, 'tab.kind', 'Expected agent tab');
    }
    final session = AgentSession(
      id: tab.id,
      projectId: projectId,
      workingDirectory: workingDirectory,
      factory: factory,
      title: tab.title,
      autoStartRelay: tab.autoStartRelay,
    );
    session
      ..sessionPath = tab.sessionPath
      ..preferredModelId = tab.preferredModelId
      ..preferredThinking = tab.preferredThinking;
    return session;
  }

  @override
  final String id;
  @override
  final String projectId;

  /// Notify the workspace when the agent closes a turn (`agent_end`).
  VoidCallback? onTurnEnd;

  /// Notify the workspace when this agent's persistable descriptor changes.
  ///
  /// This lets title, session path, and preference changes persist without
  /// waiting for the next turn to finish.
  VoidCallback? onProjectionChanged;

  /// Focus this agent's composer.
  ///
  /// `AgentComposer` registers the callback while mounted; the global
  /// Command-L/Ctrl-L shortcut invokes it.
  VoidCallback? requestComposerFocus;

  /// Identify the project directory where `pi --mode rpc` runs.
  @override
  final String workingDirectory;

  /// Distinguish a persisted "New" placeholder from a real unbooted agent.
  ///
  /// A real agent may also have an `empty` lifecycle before boot, so persistence
  /// must use this marker rather than process state.
  final bool isPlaceholder;

  /// Request relay connection at startup through `OUTPOST_PI_DIRECT_CONFIG`.
  bool autoStartRelay;

  /// Track relay connectivity reported by `outpost-pi:relay-state`.
  RelayStatus relayStatus = RelayStatus.disconnected;

  /// Persist the model selected for this agent across boots.
  ///
  /// `null` means the user has never overridden Pi's default. [_loadControls]
  /// reapplies a stored id after boot.
  String? preferredModelId;

  /// Persist and reapply the preferred thinking level after each boot.
  ThinkingLevel preferredThinking = ThinkingLevel.off;

  final AgentProcessController _process;
  StreamSubscription<AgentSessionSignal>? _signalSub;
  bool _closed = false;
  Future<void>? _closeFuture;

  /// Track the Pi session file owned by this agent.
  ///
  /// The ViewModel captures the path after the first turn and uses it to
  /// reattach the conversation when restoring the workspace.
  String? sessionPath;

  /// Snapshot session paths that existed before this agent booted.
  ///
  /// The ViewModel uses the difference after a turn to identify the new file.
  Set<String>? sessionBaseline;

  String _title;
  AgentStatus _status = AgentStatus.empty;

  /// Block duplicate sends between `sendPrompt` and `RpcAgentStart` without
  /// showing a working indicator before Pi confirms the turn.
  bool _pendingSend = false;

  /// Track locally submitted messages awaiting Pi's `message_start:user` echo.
  ///
  /// Matching echoes are ignored because the optimistic transcript already
  /// contains them. App and mesh messages are not tracked and remain visible.
  final List<String> _awaitingUserEcho = <String>[];

  AgentTurnProjection _turn = AgentTurnProjection.idle;
  CockpitTranscriptProjection _transcriptProjection =
      _emptyTranscriptProjection;
  final List<Object> _entries = <Object>[];
  final CockpitTranscriptEventLog _transcriptLog = CockpitTranscriptEventLog();
  var _transcriptEventSeq = 0;

  List<PiModel> _models = const <PiModel>[];
  List<PiCommand> _commands = const <PiCommand>[];
  PiModel? _model;
  ThinkingLevel _thinking = ThinkingLevel.off;
  ContextUsage? _ctx;

  /// Track a completed turn the user has not yet viewed for tab and workspace badges.
  bool _unseenFinish = false;
  @override
  bool get unseenFinish => _unseenFinish;

  /// Mark the latest completed turn as unseen and notify the owning pane.
  void markUnseen() {
    if (_unseenFinish) return;
    _unseenFinish = true;
    notifyListeners();
  }

  @override
  void clearUnseen() {
    if (!_unseenFinish) return;
    _unseenFinish = false;
    notifyListeners();
  }

  /// Track unresolved `extension_ui_request` cards by id until they are answered.
  final Map<String, UiRequestEntry> _openUiRequests =
      <String, UiRequestEntry>{};

  // ---- getters (UI) ---------------------------------------------------------
  @override
  String get title => _title;

  AgentSessionProjection get projection => AgentSessionProjection(
    tabId: id,
    projectId: projectId,
    title: _title,
    lifecycle: _lifecycle,
    turn: _turn,
    transcript: _transcriptProjection,
    controls: AgentControlsProjection(
      models: _models,
      commands: _commands,
      model: _model,
      thinkingLevel: _thinking,
      contextUsage: _ctx,
      preferredModelId: preferredModelId,
      preferredThinking: preferredThinking,
    ),
    relayStatus: relayStatus,
    sessionId: _transcriptSessionId,
    sessionPath: sessionPath,
    pendingLocalSend: _pendingSend,
  );

  AgentStatus get status => projection.lifecycle.toLegacyStatus();

  /// Snapshot live identity, session, relay, and control preferences for persistence.
  WorkspaceTab workspaceDescriptor({required String relativeSubpath}) =>
      WorkspaceTab.agent(
        id: id,
        relativeSubpath: relativeSubpath,
        title: projection.title,
        sessionPath: projection.sessionPath,
        autoStartRelay: autoStartRelay,
        preferredModelId: projection.controls.preferredModelId,
        preferredThinking: projection.controls.preferredThinking,
      );

  AgentTurnProjection get turn => projection.turn;

  bool get isBusy => projection.isBusy;
  bool get isAlive => projection.isAlive;
  List<Object> get entries => List<Object>.unmodifiable(_entries);
  List<PiModel> get models => projection.controls.models;
  List<PiCommand> get commands => projection.controls.commands;
  PiModel? get model => projection.controls.model;
  ThinkingLevel get thinking => projection.controls.thinkingLevel;
  ContextUsage? get contextUsage => projection.controls.contextUsage;

  AgentProcessLifecycle get _lifecycle => switch (_status) {
    AgentStatus.empty => AgentProcessLifecycle.empty,
    AgentStatus.booting => AgentProcessLifecycle.booting,
    AgentStatus.idle => AgentProcessLifecycle.idle,
    AgentStatus.crashed => AgentProcessLifecycle.crashed,
  };

  // ---- lifecycle ------------------------------------------------------------

  /// Report whether pane shutdown has begun.
  bool get isClosed => _closed;

  /// Ignore late async publications once pane shutdown begins.
  @override
  void notifyListeners() {
    if (_closed) return;
    super.notifyListeners();
  }

  /// Start `pi --mode rpc` in [workingDirectory] and project its event stream.
  ///
  /// [environment] is merged with the parent process environment, allowing
  /// `OUTPOST_PI_DIRECT_CONFIG` injection without losing PATH or HOME. A
  /// [restoreSessionPath] boots directly into that JSONL session, avoiding a
  /// later `switch_session` and duplicate extension-module evaluation.
  Future<void> boot({
    Map<String, String>? environment,
    String? restoreSessionPath,
  }) async {
    if (_closed || _status == AgentStatus.booting || isAlive) return;
    debugPrint('[agent-boot] boot() id=$id');
    _status = AgentStatus.booting;
    _turn = AgentTurnProjection.idle;
    _pendingSend = false;
    _entries.clear();
    _awaitingUserEcho.clear();
    _transcriptLog.clear();
    _transcriptProjection = _emptyTranscriptProjection;
    notifyListeners();

    await _process.boot(
      AgentSessionBootRequest(
        workingDirectory: workingDirectory,
        environment: environment,
        restoreSessionPath: restoreSessionPath,
      ),
    );
    if (_closed || !_process.isRunning) return;
    _addInfo('agent ready in $workingDirectory');
    unawaited(_loadControls());
    unawaited(_syncRelayStatus());
    if (restoreSessionPath != null) {
      unawaited(_populateTranscript(restoreSessionPath));
    }
    notifyListeners();
  }

  /// Submit a prompt optimistically when the process is alive and idle.
  ///
  /// Empty prompts are ignored unless they include images. RPC failure is
  /// appended to the transcript and clears the pending-send gate.
  Future<void> send(
    String message, {
    List<PromptImage> images = const <PromptImage>[],
  }) async {
    final text = message.trim();
    if ((text.isEmpty && images.isEmpty) || !isAlive || isBusy) {
      return;
    }
    // Add the user bubble with decoded image thumbnails. Stay idle until
    // RpcAgentStart confirms a turn so nonblocking commands do not look busy.
    _appendTranscriptEvent(
      CockpitUserMessageSubmitted(
        eventId: _nextTranscriptEventId(),
        sessionId: _transcriptSessionId,
        ts: DateTime.now(),
        clientMessageId: _nextTranscriptEventId(),
        text: text,
        images: [for (final image in images) base64Decode(image.data)],
      ),
    );
    // Track the prompt so Pi's later `message_start:user` echo is deduplicated.
    _awaitingUserEcho.add(text);
    _pendingSend = true;
    notifyListeners();
    final result = await _process.send(AgentPrompt(text: text, images: images));
    if (result == null) {
      _pendingSend = false;
      notifyListeners();
      return;
    }
    result.fold((_) {}, (error) {
      _addInfo('failed to send: ${error.message}', isError: true);
      _pendingSend = false;
      notifyListeners();
    });
  }

  /// Abort the current turn without killing the agent process.
  Future<void> stop() async {
    final result = await _process.stop();
    result?.fold((_) {}, (error) {
      _addInfo('failed to stop: ${error.message}', isError: true);
      notifyListeners();
    });
  }

  /// Start a fresh Pi session and clear the current conversation.
  ///
  /// Resets [sessionPath] so the ViewModel captures the new file after a turn.
  Future<void> startNewSession() async {
    if (!_process.isRunning || isBusy) return;
    final result = await _process.newSession();
    if (result == null) return;
    result.fold(
      (_) {
        _pendingSend = false;
        _reduceTurn(AgentTurnTransition.idle);
        _entries.clear();
        _transcriptLog.clear();
        _transcriptProjection = _emptyTranscriptProjection;
        _ctx = null;
        sessionPath = null;
        _addInfo('new session');
        notifyListeners();
        // Persist the cleared session path now; another turn may not finish
        // before the application closes.
        _notifyProjectionChanged();
      },
      (error) {
        _addInfo('failed to create session: ${error.message}', isError: true);
        notifyListeners();
      },
    );
  }

  /// Compact the current session context while the agent is idle.
  Future<void> compact() async {
    if (!_process.isRunning || isBusy) return;
    final result = await _process.compact();
    if (result == null) return;
    result.fold(
      (_) => _addInfo('context compacted'),
      (error) => _addInfo('failed to compact: ${error.message}', isError: true),
    );
    notifyListeners();
    unawaited(_refreshStats()); // the context changed
  }

  /// Apply and persist a different model while the agent is idle.
  Future<void> changeModel(PiModel model) async {
    if (!_process.isRunning || isBusy || model == _model) return;
    final result = await _process.setModel(model);
    if (result == null) return;
    result.fold(
      (applied) {
        _model = applied;
        preferredModelId = applied.id; // Persist the user's selection.
        _notifyProjectionChanged();
      },
      (error) {
        _addInfo('failed to switch model: ${error.message}', isError: true);
      },
    );
    notifyListeners();
    unawaited(_refreshStats());
  }

  /// Apply and persist a different thinking level while the agent is idle.
  Future<void> changeThinking(ThinkingLevel level) async {
    if (!_process.isRunning || isBusy || level == _thinking) return;
    final result = await _process.setThinkingLevel(level);
    if (result == null) return;
    result.fold(
      (_) {
        _thinking = level;
        preferredThinking = level; // Persist the user's selection.
        _notifyProjectionChanged();
      },
      (error) {
        _addInfo('failed to change effort: ${error.message}', isError: true);
      },
    );
    notifyListeners();
  }

  /// Switch the live Pi process to a history entry and reload its transcript.
  Future<void> loadHistory(String sessionPath) async {
    if (!_process.isRunning || isBusy) return;

    final switched = await _process.switchSession(sessionPath);
    if (switched == null) return;
    final ok = switched.fold((_) => true, (error) {
      _addInfo('failed to switch session: ${error.message}', isError: true);
      notifyListeners();
      return false;
    });
    if (!ok) return;

    await _populateTranscript(sessionPath);
  }

  /// Replace the displayed transcript with messages from a Pi session.
  ///
  /// Called after direct `--session` boot or after [loadHistory] has switched
  /// the live process.
  Future<void> _populateTranscript(String sessionPath) async {
    if (!_process.isRunning) return;

    final result = await _process.getMessages(sessionId: sessionPath);
    if (_closed || result == null) return;
    result.fold(
      (events) {
        _entries.clear();
        this.sessionPath = sessionPath;
        _awaitingUserEcho.clear();
        _transcriptLog.appendAll(events);
        _replaceProjectedTranscript();
        _status = AgentStatus.idle;
        _pendingSend = false;
        _reduceTurn(AgentTurnTransition.idle);
        notifyListeners();
        _notifyProjectionChanged();
      },
      (error) {
        _addInfo('failed to load history: ${error.message}', isError: true);
        notifyListeners();
      },
    );
  }

  /// Rename the agent and immediately request workspace persistence.
  void rename(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty || trimmed == _title) return;
    _title = trimmed;
    notifyListeners();
    _notifyProjectionChanged();
  }

  /// Persist whether this agent should connect to the relay on its next boot.
  void setAutoStartRelay(bool value) {
    if (autoStartRelay == value) return;
    autoStartRelay = value;
    notifyListeners();
    _notifyProjectionChanged();
  }

  /// Kill the process for a configuration restart while retaining the UI tab.
  Future<void> killForRestart() async {
    final wasAlive = _status == AgentStatus.booting || isAlive;
    await _process.killForRestart();
    if (wasAlive) {
      _addInfo('restarting with new configuration...');
      notifyListeners();
    }
  }

  /// Kill the process and release all session resources when its tab closes.
  @override
  Future<void> close() {
    final closing = _closeFuture;
    if (closing != null) return closing;
    _closed = true;
    return _closeFuture = _closeResources();
  }

  Future<void> _closeResources() async {
    await _process.dispose();
    await _signalSub?.cancel();
    _signalSub = null;
    await super.close();
  }

  // ---- Controls (request/response) ------------------------------------------

  /// Send a relay control command outside the LLM and transcript.
  Future<void> sendRelayControl(PiControlCommand command) async {
    await _process.sendControl(command);
  }

  /// Request relay state from Pi; the response arrives as `RpcRelayState`.
  Future<void> _syncRelayStatus() async {
    await _process.sendControl(
      PiControlCommand.relay(PiRelayControlAction.status),
    );
  }

  Future<void> _loadControls() async {
    if (_closed || !_process.isRunning) return;
    final modelsResult = await _process.availableModels();
    if (_closed) return;
    modelsResult?.fold((list) => _models = list, (_) {});
    final commandsResult = await _process.commands();
    if (_closed) return;
    commandsResult?.fold((list) => _commands = list, (_) {});
    final stateResult = await _process.state();
    if (_closed) return;
    stateResult?.fold((snapshot) {
      _model = snapshot.model;
      _thinking = snapshot.thinkingLevel;
      // `get_state` is a boot-time snapshot; do not let a stale idle snapshot
      // erase a live turn that has already arrived on the event stream.
      if (!_turn.working || snapshot.turn.working) {
        _turn = snapshot.turn;
      }
    }, (_) {});
    notifyListeners();
    unawaited(_refreshStats());
    // Reapply user preferences persisted from the previous boot.
    unawaited(_applyPreferred());
  }

  /// Silently reapply model and thinking preferences after boot.
  ///
  /// RPC failures are ignored because a persisted model may no longer exist;
  /// in that case the UI keeps Pi's default.
  Future<void> _applyPreferred() async {
    if (_closed || !_process.isRunning) return;
    final pid = preferredModelId;
    if (pid != null) {
      final target = _models.where((m) => m.id == pid).firstOrNull;
      if (target != null && target != _model) {
        final r = await _process.setModel(target);
        if (_closed) return;
        r?.fold((applied) => _model = applied, (_) {});
        notifyListeners();
      }
    }
    if (_closed) return;
    if (preferredThinking != _thinking) {
      final r = await _process.setThinkingLevel(preferredThinking);
      if (_closed) return;
      r?.fold((_) => _thinking = preferredThinking, (_) {});
      notifyListeners();
    }
  }

  Future<void> _refreshStats() async {
    if (_closed || !_process.isRunning || !isAlive) return;
    final result = await _process.sessionStats();
    if (_closed) return;
    result?.fold((usage) {
      if (usage != null) _ctx = usage;
    }, (_) {});
    notifyListeners();
  }

  // ---- signal projection ----------------------------------------------------

  void _onSignal(AgentSessionSignal signal) {
    switch (signal) {
      case AgentTurnSignal():
        _onTurnSignal(signal);
      case AgentTranscriptSignal(:final event):
        _onTranscriptSignal(event);
      case AgentLifecycleSignal(:final lifecycle, :final error):
        _status = lifecycle.toLegacyStatus();
        if (lifecycle == AgentProcessLifecycle.crashed && error != null) {
          _addInfo('failed to start: $error', isError: true);
        }
    }
    notifyListeners();
  }

  void _onTurnSignal(AgentTurnSignal signal) {
    final wasWorking = _turn.working;
    final startedAt = _turn.startedAt;
    if (signal.clearPendingSend) _pendingSend = false;
    _reduceTurn(signal.event, now: signal.now, error: signal.error);
    if (signal.closeTranscriptTurn) _closeTranscriptTurn();
    if (signal.recordWorkedDuration && wasWorking && startedAt != null) {
      _add(WorkedEntry(DateTime.now().difference(startedAt)));
    }
    if (signal.refreshStats) unawaited(_refreshStats());
    if (signal.notifyOnCompletion && wasWorking) onTurnEnd?.call();
  }

  void _onTranscriptSignal(RpcEvent event) {
    switch (event) {
      case RpcAgentStart() || RpcAgentEnd():
        return;
      case RpcTurnStart():
        _closeTranscriptTurn();
      case RpcTurnEnd():
        _closeTranscriptTurn();
      case RpcThinkingDelta(:final delta):
        _appendTranscriptEvent(
          CockpitThinkingDeltaReceived(
            eventId: _nextTranscriptEventId(),
            sessionId: _transcriptSessionId,
            ts: DateTime.now(),
            replyTo: id,
            delta: delta,
          ),
        );
      case RpcTextDelta(:final delta):
        _appendTranscriptEvent(
          CockpitAssistantDeltaReceived(
            eventId: _nextTranscriptEventId(),
            sessionId: _transcriptSessionId,
            ts: DateTime.now(),
            replyTo: id,
            delta: delta,
          ),
        );
      case RpcTextEnd(:final content):
        _appendTranscriptEvent(
          CockpitAssistantMessageCommitted(
            eventId: _nextTranscriptEventId(),
            sessionId: _transcriptSessionId,
            ts: DateTime.now(),
            messageId: _nextTranscriptEventId(),
            replyTo: id,
            text: content,
          ),
        );
      case RpcUserMessage(:final text):
        // Ignore our local echo because it is already in the transcript.
        // App or mesh messages have no local match and remain visible.
        if (_awaitingUserEcho.remove(text)) return;
        _appendTranscriptEvent(
          CockpitUserMessageConfirmed(
            eventId: _nextTranscriptEventId(),
            sessionId: _transcriptSessionId,
            ts: DateTime.now(),
            clientMessageId: _nextTranscriptEventId(),
            text: text,
          ),
        );
      case RpcToolStart(:final toolCallId, :final toolName, :final args):
        _appendTranscriptEvent(
          CockpitToolRequested(
            eventId: _nextTranscriptEventId(),
            sessionId: _transcriptSessionId,
            ts: DateTime.now(),
            toolCallId: toolCallId,
            tool: toolName,
            args: args,
          ),
        );
      case RpcToolEnd(:final toolCallId, :final isError, :final resultText):
        _appendTranscriptEvent(
          CockpitToolFinished(
            eventId: _nextTranscriptEventId(),
            sessionId: _transcriptSessionId,
            ts: DateTime.now(),
            toolCallId: toolCallId,
            result: resultText,
            error: isError ? resultText : null,
          ),
        );
      case RpcCommandResponse(:final command, :final success, :final error):
        if (!success) {
          _addInfo('command "$command" failed: ${error ?? "?"}', isError: true);
        }
      case RpcStreamError(:final message):
        _addInfo('agent error: $message', isError: true, dedup: true);
      case RpcAutoRetry(
        :final attempt,
        :final maxAttempts,
        :final delayMs,
        :final message,
      ):
        _addInfo('retrying ($attempt/$maxAttempts in ${delayMs}ms) — $message');
      case RpcDiagnostic(:final kind):
        switch (kind) {
          case RpcDiagnosticKind.childStderr:
            _addInfo(
              'agent emitted diagnostic output (content hidden)',
              dedup: true,
            );
          case RpcDiagnosticKind.streamReadFailure:
            _addInfo('agent diagnostic stream failed', isError: true);
        }
      case RpcProcessExit(:final code):
        _addInfo('process exited (code=$code)', isError: code != 0);
      case RpcNotice(:final message, :final level):
        _add(NoticeEntry(message, level.index));
      case RpcUiRequest(
        :final id,
        :final method,
        :final title,
        :final message,
        :final placeholder,
        :final defaultValue,
        :final options,
      ):
        _openUiRequests[id] = _add(
          UiRequestEntry(
            id: id,
            method: method,
            title: title,
            message: message,
            placeholder: placeholder,
            defaultValue: defaultValue,
            options: options,
          ),
        );
      case RpcRelayState(:final status):
        relayStatus = status;
      case RpcNameAssigned(:final assigned, :final changed):
        if (changed) {
          rename(assigned); // Persist the assigned name immediately.
        }
      case RpcPaired() || RpcMeshRevoked():
        return;
      case RpcUnknown():
        return;
    }
  }

  /// Answer an interactive extension request and resolve its transcript card.
  ///
  /// [response] carries `value`, `confirmed`, or `cancelled`; [label] is the
  /// human-readable result retained on the resolved card.
  void respondUi(String id, RpcUiResponse response, String label) {
    final entry = _openUiRequests.remove(id);
    if (entry != null) {
      entry.resolved = true;
      entry.answerLabel = label;
    }
    unawaited(_process.respondUi(id, response));
    notifyListeners();
  }

  // ---- helpers --------------------------------------------------------------

  void _reduceTurn(
    AgentTurnTransition transition, {
    DateTime? now,
    String? error,
  }) {
    _turn = reduceAgentTurnProjection(
      _turn,
      transition,
      now: now,
      error: error,
    );
  }

  T _add<T extends AgentEntry>(T entry) {
    _entries.add(entry);
    return entry;
  }

  String get _transcriptSessionId => sessionPath ?? id;

  String _nextTranscriptEventId() => '$id:${_transcriptEventSeq++}';

  void _appendTranscriptEvent(CockpitTranscriptEvent event) {
    _transcriptLog.append(event);
    _replaceProjectedTranscript();
  }

  void _closeTranscriptTurn() {
    if (_transcriptLog.isEmpty) return;
    if (_transcriptProjection.turn.status == CockpitTranscriptTurnStatus.idle) {
      return;
    }
    _appendTranscriptEvent(
      CockpitAssistantDoneReceived(
        eventId: _nextTranscriptEventId(),
        sessionId: _transcriptSessionId,
        ts: DateTime.now(),
        replyTo: id,
      ),
    );
  }

  void _replaceProjectedTranscript() {
    final firstProjectedIndex = _entries.indexWhere(
      _isProjectedTranscriptEntry,
    );
    _entries.removeWhere(_isProjectedTranscriptEntry);
    _transcriptProjection = deriveCockpitTranscript(
      _transcriptLog.forSession(_transcriptSessionId),
    );
    final newEntries = _transcriptProjection.entries;
    final insertionIndex = firstProjectedIndex < 0
        ? _entries.length
        : firstProjectedIndex > _entries.length
        ? _entries.length
        : firstProjectedIndex;
    _entries.insertAll(insertionIndex, newEntries);
  }

  bool _isProjectedTranscriptEntry(Object entry) {
    return entry is ProjectedTranscriptMessage;
  }

  void _notifyProjectionChanged() {
    onProjectionChanged?.call();
  }

  void _addInfo(String text, {bool isError = false, bool dedup = false}) {
    if (dedup) {
      final last = _entries.isNotEmpty ? _entries.last : null;
      if (last is InfoEntry && last.text == text) return;
    }
    _add(InfoEntry(text, isError: isError));
  }
}

const _emptyTranscriptProjection = CockpitTranscriptProjection(
  entries: <ProjectedTranscriptMessage>[],
  turn: CockpitTranscriptTurnView(status: CockpitTranscriptTurnStatus.idle),
);

extension on AgentProcessLifecycle {
  AgentStatus toLegacyStatus() => switch (this) {
    AgentProcessLifecycle.empty => AgentStatus.empty,
    AgentProcessLifecycle.booting => AgentStatus.booting,
    AgentProcessLifecycle.idle => AgentStatus.idle,
    AgentProcessLifecycle.running => AgentStatus.idle,
    AgentProcessLifecycle.crashed => AgentStatus.crashed,
  };
}
