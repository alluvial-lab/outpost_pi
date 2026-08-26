import 'dart:async';
import 'dart:convert';

import 'package:cockpit/app/cockpit/domain/contracts/file_reader.dart';
import 'package:cockpit/app/cockpit/domain/contracts/notifier.dart';
import 'package:cockpit/app/cockpit/domain/contracts/rpc_gateway_factory.dart';
import 'package:cockpit/app/cockpit/domain/contracts/session_history.dart';
import 'package:cockpit/app/cockpit/domain/contracts/terminal_gateway_factory.dart';
import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';
import 'package:cockpit/app/cockpit/domain/entities/project.dart';
import 'package:cockpit/app/cockpit/domain/entities/thinking_level.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_document.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_tab.dart';
import 'package:cockpit/app/cockpit/ui/session/agent_session.dart';
import 'package:cockpit/app/cockpit/ui/session/file_viewer_session.dart';
import 'package:cockpit/app/cockpit/ui/session/pane_item.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_session.dart';
import 'package:cockpit/app/cockpit/ui/states/pane_node.dart';
import 'package:cockpit/app/core/data/lsp/lsp_server_pool.dart';
import 'package:cockpit/app/core/ui/async_action.dart';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// Handle completion of a projected agent turn.
typedef WorkspaceProjectionTurnEnd = void Function(AgentSession session);

/// Handle a live tab descriptor change that requires workspace persistence.
typedef WorkspaceProjectionDescriptorChanged = void Function(String projectId);

/// Surface a file-watch failure to the projection owner.
typedef WorkspaceProjectionFileWatchError =
    void Function(String path, Object error, StackTrace stackTrace);

/// Live projection of a persisted [WorkspaceDocument] into disposable UI tabs.
///
/// The document owns pane shape and tab descriptors. This adapter owns the live
/// [PaneItem] instances behind those descriptors: agent RPC sessions, terminal
/// PTYs, file viewer buffers, and file-watch debounce timers.
final class WorkspaceProjection {
  WorkspaceProjection({
    required RpcGatewayFactory rpcFactory,
    required TerminalGatewayFactory terminalFactory,
    required FileReader fileReader,
    required SessionHistory history,
    required Notifier notifier,
    required this.lsp,
    required WorkspaceProjectionFileWatchError onFileWatchError,
    VoidCallback? onChanged,
    WorkspaceProjectionTurnEnd? onAgentTurnEnd,
    WorkspaceProjectionDescriptorChanged? onDescriptorChanged,
  }) : _rpcFactory = rpcFactory,
       _terminalFactory = terminalFactory,
       _fileReader = fileReader,
       _history = history,
       _notifier = notifier,
       _onFileWatchError = onFileWatchError,
       _onChanged = onChanged ?? _noop,
       _onAgentTurnEnd = onAgentTurnEnd,
       _onDescriptorChanged = onDescriptorChanged;

  final RpcGatewayFactory _rpcFactory;
  final TerminalGatewayFactory _terminalFactory;
  final FileReader _fileReader;
  final SessionHistory _history;
  final Notifier _notifier;
  final WorkspaceProjectionFileWatchError _onFileWatchError;

  /// Kept as part of the projection boundary for file-viewer/LSP coordination.
  final LspServerPool lsp;

  final VoidCallback _onChanged;
  final WorkspaceProjectionTurnEnd? _onAgentTurnEnd;
  final WorkspaceProjectionDescriptorChanged? _onDescriptorChanged;

  final Map<String, PaneItem> _items = <String, PaneItem>{};
  final Map<String, StreamSubscription<void>> _fileWatchers =
      <String, StreamSubscription<void>>{};
  final Map<String, Timer> _fileWatchDebounce = <String, Timer>{};

  static void _noop() {}

  PaneItem? item(String id) => _items[id];

  Iterable<PaneItem> get items => _items.values;

  Iterable<PaneItem> itemsForProject(String projectId) =>
      _items.values.where((item) => item.projectId == projectId);

  int notificationCount(String projectId) =>
      itemsForProject(projectId).where((item) => item.unseenFinish).length;

  /// Realize a persisted tab descriptor as a live, owned UI resource.
  ///
  /// Returns `false` when the descriptor cannot be realized, such as an invalid
  /// viewer path. Agent realization awaits boot; terminal and empty tabs are
  /// created synchronously.
  Future<bool> realize(WorkspaceTab tab, Project project) async {
    String cwdOf() {
      final sub = tab.relativeSubpath;
      return sub.isEmpty ? project.path : '${project.path}/$sub';
    }

    switch (tab.kind) {
      case WorkspaceTabKind.terminal:
        createTerminal(
          id: tab.id,
          projectId: project.id,
          workingDirectory: cwdOf(),
          title: tab.title,
        );
        return true;
      case WorkspaceTabKind.viewer:
        final path = tab.filePath;
        if (path == null) return false;
        return (await createViewer(
              id: tab.id,
              projectId: project.id,
              path: path,
            )) !=
            null;
      case WorkspaceTabKind.empty:
        createEmpty(id: tab.id, projectId: project.id, title: tab.title);
        return true;
      case WorkspaceTabKind.agent:
        return realizeAgent(tab, project);
    }
  }

  /// Create and own a placeholder agent tab without starting an RPC process.
  AgentSession createEmpty({
    required String id,
    required String projectId,
    String? title,
  }) {
    final session = AgentSession(
      id: id,
      projectId: projectId,
      workingDirectory: '',
      factory: _rpcFactory,
      title: title ?? 'New',
      isPlaceholder: true,
    );
    _items[session.id] = session;
    return session;
  }

  /// Create and own a terminal tab, starting its PTY immediately.
  TerminalSession createTerminal({
    required String id,
    required String projectId,
    required String workingDirectory,
    String? title,
  }) {
    final terminal = TerminalSession(
      id: id,
      projectId: projectId,
      workingDirectory: workingDirectory,
      gateway: _terminalFactory.create(),
      title: title,
    );
    _items[terminal.id] = terminal;
    return terminal;
  }

  /// Restore and boot an agent from a persisted descriptor.
  ///
  /// Returns `false` for non-agent descriptors. A valid descriptor is inserted
  /// before boot so this projection owns cleanup even if startup fails.
  Future<bool> realizeAgent(WorkspaceTab tab, Project project) async {
    if (tab.kind != WorkspaceTabKind.agent) return false;
    final cwd = tab.relativeSubpath.isEmpty
        ? project.path
        : '${project.path}/${tab.relativeSubpath}';
    final session = AgentSession.fromWorkspaceTab(
      tab: tab,
      projectId: project.id,
      workingDirectory: cwd,
      factory: _rpcFactory,
    );
    _wireAgent(session, project.id);
    _items[session.id] = session;
    await _bootAgent(session, project, tab.sessionPath);
    return true;
  }

  /// Create, own, and asynchronously boot a new agent tab.
  ///
  /// The returned session is available immediately; callers observe its boot
  /// lifecycle through the session projection.
  AgentSession createAgent({
    required String id,
    required Project project,
    required String workingDirectory,
    String? title,
    bool autoStartRelay = false,
    String? restoreSessionPath,
    String? preferredModelId,
    ThinkingLevel preferredThinking = ThinkingLevel.off,
  }) {
    final relativeSubpath = _subOf(workingDirectory, project.path);
    final session = AgentSession.fromWorkspaceTab(
      tab: WorkspaceTab.agent(
        id: id,
        relativeSubpath: relativeSubpath,
        title: title,
        sessionPath: restoreSessionPath,
        autoStartRelay: autoStartRelay,
        preferredModelId: preferredModelId,
        preferredThinking: preferredThinking,
      ),
      projectId: project.id,
      workingDirectory: workingDirectory,
      factory: _rpcFactory,
    );
    _wireAgent(session, project.id);
    _items[session.id] = session;
    unawaited(_bootAgent(session, project, restoreSessionPath));
    return session;
  }

  /// Read [path] and create an owned viewer with live file watching.
  ///
  /// Returns `null` when the file reader classifies the path as unsupported.
  Future<FileViewerSession?> createViewer({
    required String id,
    required String projectId,
    required String path,
    bool isPreview = false,
  }) async {
    final view = await _fileReader.read(path);
    if (view is FileViewUnsupported) return null;
    final viewer = FileViewerSession(
      id: id,
      projectId: projectId,
      path: path,
      view: view,
      isPreview: isPreview,
    );
    _items[viewer.id] = viewer;
    _watchFileViewer(viewer);
    return viewer;
  }

  /// Replace a live viewer's path and content while retaining its tab identity.
  ///
  /// Returns `false` for an unsupported path or a non-viewer id.
  Future<bool> replaceViewerPath(String id, String path) async {
    final fresh = await _fileReader.read(path);
    if (fresh is FileViewUnsupported) return false;
    final current = _items[id];
    if (current is! FileViewerSession) return false;
    current.path = path;
    current.view = fresh;
    current.dirty = false;
    current.notifyItemChanged();
    _watchFileViewer(current);
    _onChanged();
    return true;
  }

  /// Save editor content and refresh the viewer's classified representation.
  ///
  /// Returns `false` when [id] is not a viewer or the write fails.
  Future<bool> saveViewer(String id, String content) async {
    final viewer = _items[id];
    if (viewer is! FileViewerSession) return false;
    final ok = await _fileReader.write(viewer.path, content);
    if (!ok) return false;
    final fresh = await _fileReader.read(viewer.path);
    final current = _items[id];
    if (current is FileViewerSession && fresh is! FileViewUnsupported) {
      current.view = fresh;
      _onChanged();
    }
    return true;
  }

  /// Retarget every viewer at or below [from] after a filesystem rename.
  ///
  /// Reloads supported content, reattaches watchers, and preserves each tab id.
  Future<void> retargetViewersUnder(String from, String to) async {
    for (final item in List<PaneItem>.of(_items.values)) {
      if (item is! FileViewerSession || !_isUnder(item.path, from)) continue;
      final newPath = item.path == from
          ? to
          : '$to${item.path.substring(from.length)}';
      item.retarget(newPath);
      final fresh = await _fileReader.read(newPath);
      final current = _items[item.id];
      if (current is! FileViewerSession) continue;
      if (fresh is! FileViewUnsupported) current.view = fresh;
      _watchFileViewer(current);
    }
    _onChanged();
  }

  /// Clear an agent tab's unseen-completion marker when it becomes visible.
  void clearUnseen(String id) {
    final item = _items[id];
    if (item != null && item.unseenFinish) item.clearUnseen();
  }

  /// Remove a tab immediately, then await its watcher and live resources.
  Future<void> disposeTab(String id) async {
    final watcher = _fileWatchers.remove(id);
    _fileWatchDebounce.remove(id)?.cancel();
    final item = _items.remove(id);
    await watcher?.cancel();
    await item?.close();
  }

  /// Dispose every live tab described by a project's workspace document.
  Future<void> disposeProject(WorkspaceDocument document) {
    return Future.wait(document.tabs.keys.map(disposeTab));
  }

  /// Snapshot a live tab as a persistable workspace descriptor.
  WorkspaceTab descriptorFor(PaneItem item, Project project) {
    if (item is TerminalSession) {
      return WorkspaceTab.terminal(
        id: item.id,
        relativeSubpath: _subOf(item.workingDirectory, project.path),
        title: item.title,
      );
    }
    if (item is FileViewerSession) {
      return WorkspaceTab.viewer(id: item.id, filePath: item.path);
    }
    final agent = item as AgentSession;
    return descriptorForAgent(agent, project);
  }

  /// Snapshot an agent or placeholder with a project-relative working path.
  WorkspaceTab descriptorForAgent(AgentSession session, Project project) {
    if (session.isPlaceholder) {
      return WorkspaceTab.empty(id: session.id, title: session.title);
    }
    return session.workspaceDescriptor(
      relativeSubpath: _subOf(session.workingDirectory, project.path),
    );
  }

  /// Refresh a document's tab descriptors from currently owned live tabs.
  WorkspaceDocument documentWithLiveTabs(
    Project project,
    WorkspaceDocument document,
  ) {
    final tabs = <String, WorkspaceTab>{};
    for (final leaf in leaves(document.root)) {
      for (final id in leaf.tabs) {
        final item = _items[id];
        final tab = item == null
            ? document.tabs[id]
            : descriptorFor(item, project);
        if (tab != null) tabs[id] = tab;
      }
    }
    return document.copyWith(tabs: tabs);
  }

  /// Capture the session file created after an agent's baseline snapshot.
  ///
  /// Leaves the session unchanged when no unambiguous new history entry exists.
  Future<void> captureSessionPath(AgentSession session) async {
    final baseline = session.sessionBaseline;
    if (baseline == null || session.sessionPath != null) return;
    final now = await _history.sessionsFor(session.workingDirectory);
    final fresh = now.where((entry) => !baseline.contains(entry.path)).toList();
    if (fresh.isEmpty) return;
    fresh.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    session.sessionPath = fresh.first.path;
    _notifyDescriptorChanged(session.projectId);
  }

  /// Mark an inactive completed agent unseen and notify when the window is out of focus.
  Future<void> notifyIfNeeded(
    AgentSession session, {
    required bool isActiveTab,
    required bool notificationsEnabled,
    required String workspace,
  }) async {
    if (!isActiveTab) {
      session.markUnseen();
      _onChanged();
    }

    if (!notificationsEnabled) return;

    final windowFocused = await windowManager.isFocused();
    if (!windowFocused) {
      await _notifier.agentFinished(
        agentName: session.title,
        workspace: workspace,
      );
    }
  }

  /// Dispose all projected tabs, file watchers, and debounce timers.
  Future<void> dispose() {
    final ids = _items.keys.toList(growable: false);
    return Future.wait(ids.map(disposeTab));
  }

  void _wireAgent(AgentSession session, String projectId) {
    session.onTurnEnd = () => _onAgentTurnEnd?.call(session);
    session.onProjectionChanged = () => _notifyDescriptorChanged(projectId);
  }

  void _notifyDescriptorChanged(String projectId) {
    _onDescriptorChanged?.call(projectId);
    _onChanged();
  }

  Future<void> _bootAgent(
    AgentSession session,
    Project project,
    String? restoreSessionPath,
  ) async {
    final baseline = (await _history.sessionsFor(
      session.workingDirectory,
    )).map((entry) => entry.path).toSet();
    if (session.isClosed) return;
    session.sessionBaseline = baseline;
    await session.boot(
      environment: _buildDirectConfig(session, project),
      restoreSessionPath: restoreSessionPath,
    );
  }

  Map<String, String> _buildDirectConfig(
    AgentSession session,
    Project project,
  ) {
    return {
      'OUTPOST_PI_DIRECT_CONFIG': jsonEncode(<String, dynamic>{
        'agent_name': session.title,
        'workspace': project.name,
        'auto_start_relay': session.autoStartRelay,
      }),
      'OUTPOST_PI_DAEMON': '1',
    };
  }

  void _watchFileViewer(FileViewerSession viewer) {
    // A/V live reload is disabled: refreshing would recreate the player mid-play.
    if (viewer.view is FileViewAudio || viewer.view is FileViewVideo) return;
    final id = viewer.id;
    final path = viewer.path;
    _fileWatchers.remove(id)?.cancel();
    _fileWatchDebounce.remove(id)?.cancel();
    try {
      _fileWatchers[id] = _fileReader
          .watch(path)
          .listen(
            (_) {
              _fileWatchDebounce[id]?.cancel();
              _fileWatchDebounce[id] = Timer(
                const Duration(milliseconds: 120),
                () {
                  _fileWatchDebounce.remove(id);
                  ownAsync(_reloadFileViewer(id, path));
                },
              );
            },
            onError: (Object error, StackTrace stackTrace) {
              _onFileWatchError(path, error, stackTrace);
            },
          );
    } catch (error, stackTrace) {
      _onFileWatchError(path, error, stackTrace);
    }
  }

  Future<void> _reloadFileViewer(String id, String path) async {
    if (_items[id] is! FileViewerSession) return;
    try {
      final fresh = await _fileReader.read(path);
      if (fresh is FileViewUnsupported) return;
      final current = _items[id];
      if (current is! FileViewerSession || current.path != path) return;
      current.view = fresh;
      current.notifyItemChanged();
      _onChanged();
    } catch (error, stackTrace) {
      _onFileWatchError(path, error, stackTrace);
    }
  }

  bool _isUnder(String path, String root) =>
      path == root || path.startsWith('$root/');

  String _subOf(String cwd, String root) {
    final c = cwd.replaceAll('\\', '/');
    final r = root.replaceAll('\\', '/');
    if (c == r) return '';
    final prefix = r.endsWith('/') ? r : '$r/';
    return c.startsWith(prefix) ? c.substring(prefix.length) : '';
  }
}
