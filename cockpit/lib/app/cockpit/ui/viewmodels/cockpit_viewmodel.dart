import 'dart:async';
import 'dart:io' show Directory, FileSystemEvent;
import 'dart:math' show max;

import 'package:cockpit/app/cockpit/domain/contracts/app_launcher.dart';
import 'package:cockpit/app/cockpit/domain/contracts/file_reader.dart';
import 'package:cockpit/app/cockpit/domain/contracts/file_searcher.dart';
import 'package:cockpit/app/cockpit/domain/contracts/file_system_mutator.dart';
import 'package:cockpit/app/cockpit/domain/contracts/file_system_reader.dart';
import 'package:cockpit/app/cockpit/domain/contracts/folder_lister.dart';
import 'package:cockpit/app/cockpit/domain/contracts/git_status_reader.dart';
import 'package:cockpit/app/cockpit/domain/contracts/notifier.dart';
import 'package:cockpit/app/cockpit/domain/contracts/project_repository.dart';
import 'package:cockpit/app/cockpit/domain/contracts/rpc_gateway_factory.dart';
import 'package:cockpit/app/cockpit/domain/contracts/session_history.dart';
import 'package:cockpit/app/cockpit/domain/contracts/terminal_gateway_factory.dart';
import 'package:cockpit/app/cockpit/domain/contracts/workspace_layout_store.dart';
import 'package:cockpit/app/cockpit/domain/contracts/worktree_manager.dart';
import 'package:cockpit/app/cockpit/domain/entities/file_node.dart';
import 'package:cockpit/app/cockpit/domain/entities/git_file_status.dart';
import 'package:cockpit/app/cockpit/domain/entities/git_info.dart';
import 'package:cockpit/app/cockpit/domain/entities/launchable_app.dart';
import 'package:cockpit/app/cockpit/domain/entities/pi_command.dart';
import 'package:cockpit/app/cockpit/domain/entities/project.dart';
import 'package:cockpit/app/cockpit/domain/entities/session_info.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_document.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_document_commands.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_tab.dart';
import 'package:cockpit/app/cockpit/domain/entities/worktree.dart';
import 'package:cockpit/app/cockpit/domain/validators/file_name_validator.dart';
import 'package:cockpit/app/core/data/lsp/lsp_server_pool.dart';
import 'package:cockpit/app/core/data/lsp/lsp_text_edit.dart';
import 'package:cockpit/app/core/domain/entities/lsp_diagnostic.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/core/ui/async_action.dart';
import 'package:cockpit/app/cockpit/ui/session/agent_session.dart';
import 'package:cockpit/app/cockpit/ui/session/file_viewer_session.dart';
import 'package:cockpit/app/cockpit/ui/session/pane_item.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_session.dart';
import 'package:cockpit/app/cockpit/ui/states/pane_node.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/workspace_projection.dart';
import 'package:flutter/foundation.dart';

/// Coordinate projects, per-project pane trees, live sessions, and focus.
///
/// Each project owns a [WorkspaceDocument] in [_documents]. Switching projects
/// changes only the displayed tree because the page keeps every tree mounted in
/// an `IndexedStack`. Live tabs and processes remain owned by [_workspace] and
/// continue independently of which tree is visible.
///
/// Pane operations apply only to the active project identified by
/// [_selectedProjectId].
class CockpitViewModel extends ChangeNotifier {
  CockpitViewModel(
    ProjectRepository projects,
    RpcGatewayFactory rpcFactory,
    FolderLister folders,
    SessionHistory history,
    Notifier notifier,
    FileSystemReader fileSystem,
    TerminalGatewayFactory terminalFactory,
    FileReader fileReader,
    WorkspaceLayoutStore layoutStore,
    GitStatusReader gitReader,
    FileSearcher fileSearcher,
    AppLauncherGateway launcher,
    WorktreeManager worktreeMgr,
    FileSystemMutator fileMutator,
    LspServerPool lsp,
  ) : _projects = projects,
      _folders = folders,
      _history = history,
      _fileSystem = fileSystem,
      _layoutStore = layoutStore,
      _gitReader = gitReader,
      _fileSearcher = fileSearcher,
      _launcher = launcher,
      _worktreeMgr = worktreeMgr,
      _fileMutator = fileMutator,
      _lsp = lsp {
    _workspace = WorkspaceProjection(
      rpcFactory: rpcFactory,
      terminalFactory: terminalFactory,
      fileReader: fileReader,
      history: history,
      notifier: notifier,
      lsp: lsp,
      onChanged: notifyListeners,
      onAgentTurnEnd: _onAgentTurnEnd,
      onDescriptorChanged: _scheduleSave,
    );
  }

  final ProjectRepository _projects;
  final FolderLister _folders;
  final SessionHistory _history;
  final FileSystemReader _fileSystem;
  final WorkspaceLayoutStore _layoutStore;
  final GitStatusReader _gitReader;
  final FileSearcher _fileSearcher;
  final AppLauncherGateway _launcher;
  final WorktreeManager _worktreeMgr;
  final FileSystemMutator _fileMutator;
  final LspServerPool _lsp;
  late final WorkspaceProjection _workspace;

  List<LaunchableApp> _availableApps = const [];

  final List<Project> _projectList = <Project>[];
  String? _selectedProjectId;

  /// Hold pane shape, focus, and tab descriptors for each active project.
  final Map<String, WorkspaceDocument> _documents =
      <String, WorkspaceDocument>{};

  /// Cache layouts loaded from Hive until each project is activated lazily.
  ///
  /// A `null` value means the project has no saved layout.
  final Map<String, Map<String, dynamic>?> _savedLayouts =
      <String, Map<String, dynamic>?>{};

  /// Debounce persistence independently per project during continuous resize.
  final Map<String, Timer> _saveTimers = <String, Timer>{};

  /// Suppress persistence while a project layout is only partially restored.
  bool _restoring = false;

  /// Cache branch and dirty state per project.
  ///
  /// A missing or `null` value means the path is not a Git repository.
  final Map<String, GitInfo?> _gitInfo = <String, GitInfo?>{};

  /// Index Git status by project-relative file and aggregated folder path.
  ///
  /// Folder entries carry the strongest descendant status through
  /// [GitFileStatus.strongest] and drive file-tree coloring.
  final Map<String, Map<String, GitFileStatus>> _gitTree =
      <String, Map<String, GitFileStatus>>{};

  /// Watch the selected project's working tree and debounce filesystem bursts.
  StreamSubscription<FileSystemEvent>? _gitWatch;
  Timer? _gitWatchDebounce;
  String? _gitWatchPath;

  /// Cache each root workspace's worktrees in `git worktree list` order.
  ///
  /// Git, not Hive, owns their existence. Reconciliation also adds the same
  /// [Project] values to [_projectList] for lookup and the `IndexedStack`.
  final Map<String, List<Project>> _worktrees = <String, List<Project>>{};

  /// Increment after filesystem mutations so `FileTreePanel` reloads open folders.
  int _fileTreeRevision = 0;
  int get fileTreeRevision => _fileTreeRevision;

  /// Track the file-tree selection used for row highlighting.
  String? _selectedFileInTree;
  String? get selectedFileInTree => _selectedFileInTree;

  bool _railVisible = true;
  bool _treeVisible = true;
  bool _ready = false;
  String? _initializationError;
  int _seq = 0;

  /// Mirror the app-scoped notification preference into this page-scoped model.
  bool _notificationsEnabled = true;

  /// Gate future end-of-turn desktop notifications with [value].
  void setNotificationsEnabled(bool value) => _notificationsEnabled = value;

  /// Supply the design palette used for new project avatars.
  static const List<int> _palette = <int>[
    0xFF6E56CF,
    0xFFE5484D,
    0xFF1AA5A0,
    0xFF3FB868,
    0xFFE0A33A,
    0xFF2F6FF0,
  ];

  String _nid(String prefix) => '$prefix${_seq++}';

  // ---- getters --------------------------------------------------------------
  List<Project> get projects => List<Project>.unmodifiable(_projectList);

  /// Return root workspaces in the user's persisted rail order.
  List<Project> get rootProjects {
    final roots = _projectList.where((p) => p.parentId == null).toList();
    // Use creation time as a stable fallback for equal manual order values.
    roots.sort((a, b) {
      final byOrder = a.order.compareTo(b.order);
      return byOrder != 0 ? byOrder : a.createdAt.compareTo(b.createdAt);
    });
    return List<Project>.unmodifiable(roots);
  }

  /// Return a root workspace's worktrees in Git order, or an empty list.
  List<Project> worktreesOf(String rootId) =>
      _worktrees[rootId] ?? const <Project>[];

  String? get selectedProjectId => _selectedProjectId;
  Project? get selectedProject => _projectById(_selectedProjectId);

  /// Build the selected top-bar title, including its parent for a worktree.
  ///
  /// Returns `null` when no project is selected.
  String? get selectedDisplayTitle {
    final p = selectedProject;
    if (p == null) return null;
    final parentId = p.parentId;
    if (parentId == null) return p.name;
    final root = _projectById(parentId);
    return root == null ? p.name : '${root.name} · ${p.name}';
  }

  /// Report whether [init] has finished loading and activating the workspace.
  bool get ready => _ready;

  /// Explain a workspace recovery failure while keeping the shell usable.
  String? get initializationError => _initializationError;

  bool get railVisible => _railVisible;
  bool get treeVisible => _treeVisible;
  List<LaunchableApp> get availableApps =>
      List<LaunchableApp>.unmodifiable(_availableApps);

  /// Resolve a live tab resource by its workspace tab id.
  PaneItem? session(String id) => _workspace.item(id);

  /// Return branch and dirty state, or `null` for a non-Git project.
  GitInfo? gitInfo(String projectId) => _gitInfo[projectId];

  /// Resolve display status for an absolute file or folder in the selected project.
  ///
  /// Returns `null` when the path is clean or outside a Git repository.
  GitFileStatus? gitStatusForPath(String absolutePath) {
    final pid = _selectedProjectId;
    if (pid == null) return null;
    final root = _projectById(pid)?.path;
    if (root == null) return null;
    final rel = _subOf(absolutePath, root);
    if (rel.isEmpty) return null;
    // Prefer explicit aggregated changes, then inherit untracked or ignored
    // status from a collapsed root that covers this path.
    final dirty = _gitTree[pid]?[rel];
    if (dirty != null) return dirty;
    final info = _gitInfo[pid];
    if (info == null) return null;
    if (info.isUntracked(rel)) return GitFileStatus.untracked;
    if (info.isIgnored(rel)) return GitFileStatus.ignored;
    return null;
  }

  /// Return the active tab in the focused pane.
  PaneItem? get focusedAgent {
    final id = _focusedAgentId;
    return id == null ? null : _workspace.item(id);
  }

  /// Lazily list children for a file-tree folder.
  Future<List<FileNode>> listChildren(String path) =>
      _fileSystem.children(path);

  /// Search [cwd] for relative paths matching an `@` autocomplete [query].
  Future<List<String>> searchFiles(String cwd, String query) =>
      _fileSearcher.search(cwd, query);

  /// Open a supported file in a viewer tab and focus its destination pane.
  ///
  /// Without [inPane], uses the focused pane. Unsupported or oversized content
  /// is ignored. When [isPreview] is `true`, reuses an existing preview where
  /// possible; callers pass `false` for a pinned double-click tab.
  Future<void> openFile(
    String path, {
    String? inPane,
    bool isPreview = true,
  }) async {
    final document = _activeDocument;
    final projectId = document?.projectId;
    final paneId =
        inPane ?? (projectId == null ? null : focusedPaneId(projectId));
    if (document == null || projectId == null || paneId == null) return;
    final leaf = findLeaf(document.root, paneId);
    if (leaf == null) return;

    // Reuse an existing preview when possible; pinned opens create normal tabs.
    FileViewerSession? previewCandidate;
    for (final tabId in leaf.tabs) {
      final item = _workspace.item(tabId);
      if (item is FileViewerSession) {
        // Select an existing viewer and pin it when requested.
        if (item.path == path) {
          if (!isPreview && item.isPreview) item.pin();
          _applyWorkspaceCommand(
            (doc) => WorkspaceDocumentCommands.selectTab(
              doc,
              paneId: paneId,
              tabId: tabId,
            ),
          );
          return;
        }
        // Retain the first preview as a reuse candidate.
        if (isPreview && item.isPreview && previewCandidate == null) {
          previewCandidate = item;
        }
      }
    }

    // Reuse a preview candidate by replacing its content.
    if (isPreview && previewCandidate != null) {
      final replaced = await _workspace.replaceViewerPath(
        previewCandidate.id,
        path,
      );
      if (!replaced) return;
      _applyWorkspaceCommand(
        (doc) => WorkspaceDocumentCommands.replaceTab(
          doc,
          paneId: paneId,
          oldTabId: previewCandidate!.id,
          newTab: WorkspaceTab.viewer(id: previewCandidate.id, filePath: path),
          disposeOldTab: false,
        ),
      );
      return;
    }

    // Create a new preview or pinned viewer.
    final viewer = await _workspace.createViewer(
      id: _nid('v'),
      projectId: projectId,
      path: path,
      isPreview: isPreview,
    );
    if (viewer == null) return; // Ignore unsupported or oversized content.
    final viewerTab = WorkspaceTab.viewer(id: viewer.id, filePath: path);

    // Replace an empty placeholder or active preview; otherwise append a tab.
    final current = _activeDocument?.root ?? document.root;
    final lf = findLeaf(current, paneId);
    final activeTabId = lf?.active;
    final activeTab = activeTabId == null ? null : _workspace.item(activeTabId);
    final only = lf?.tabs.length == 1 ? _workspace.item(lf!.tabs.first) : null;

    late final bool applied;
    if (isPreview && activeTab is FileViewerSession && !activeTab.isPreview) {
      // Append beside a pinned viewer rather than replacing it.
      applied = _applyWorkspaceCommand(
        (doc) => WorkspaceDocumentCommands.appendTab(
          doc,
          paneId: paneId,
          tab: viewerTab,
        ),
      );
    } else if (isPreview &&
        activeTab is FileViewerSession &&
        activeTab.isPreview) {
      // Replace the active preview with the new preview.
      applied = _applyWorkspaceCommand(
        (doc) => WorkspaceDocumentCommands.replaceActiveTab(
          doc,
          paneId: paneId,
          newTab: viewerTab,
        ),
      );
    } else if (lf != null && only is AgentSession && only.isPlaceholder) {
      // Replace the empty placeholder.
      applied = _applyWorkspaceCommand(
        (doc) => WorkspaceDocumentCommands.replaceTab(
          doc,
          paneId: paneId,
          oldTabId: lf.tabs.first,
          newTab: viewerTab,
        ),
      );
    } else {
      // Append a new viewer tab.
      applied = _applyWorkspaceCommand(
        (doc) => WorkspaceDocumentCommands.appendTab(
          doc,
          paneId: paneId,
          tab: viewerTab,
        ),
      );
    }
    if (!applied) await _workspace.disposeTab(viewer.id);
  }

  /// Select a file-tree path and update its highlight.
  void selectFileInTree(String path) {
    _selectedFileInTree = path;
    notifyListeners();
  }

  /// Save viewer edits and refresh the content classification.
  ///
  /// Returns `true` on success. Concurrent agent writes remain last-write-wins.
  Future<bool> saveFile(String sessionId, String content) =>
      _workspace.saveViewer(sessionId, content);

  // ---- LSP (diagnostics and formatting) -------------------------------------

  /// Stream merged diagnostics for file viewers to filter by document URI.
  Stream<LspDiagnosticsBatch> get lspDiagnostics => _lsp.diagnostics;

  /// Open [path] in its language server with the project as fallback root.
  ///
  /// The fallback applies when marker discovery cannot find a nearer root.
  Future<void> lspOpenDocument(String path, String text, String projectId) =>
      _lsp.openDocument(
        path: path,
        text: text,
        fallbackRoot: _projectById(projectId)?.path,
      );

  /// Send a full-document `didChange` update to the language server.
  Future<void> lspChangeDocument(String path, String text) =>
      _lsp.changeDocument(path: path, text: text);

  /// Close a language-server document and release its pool reference.
  Future<void> lspCloseDocument(String path) => _lsp.closeDocument(path);

  /// Apply command overrides to language servers spawned after this call.
  ///
  /// Existing servers retain their previous command until restarted.
  void applyLspCommands(Map<String, String> commands) {
    _lsp.commandOverrides = commands;
  }

  /// Stream language-server start, stop, and restart pulses for live status UI.
  Stream<void> get lspStatusChanges => _lsp.statusChanges;

  /// Return the focused viewer path, or `null` for non-file tabs.
  String? get focusedFilePath {
    final s = focusedAgent;
    return s is FileViewerSession ? s.path : null;
  }

  /// Return language and running state for the focused supported file.
  ///
  /// Returns `null` so the status bar stays empty for unsupported tab types.
  LspDocStatus? get focusedLspStatus {
    final path = focusedFilePath;
    return path == null ? null : _lsp.statusForPath(path);
  }

  /// Restart the language server associated with the focused file.
  Future<void> restartFocusedLsp() async {
    final path = focusedFilePath;
    if (path == null) return;
    await _lsp.restartForPath(path);
    notifyListeners();
  }

  /// Restart every server for a language so a command override takes effect.
  Future<void> restartLspLanguage(String languageId) async {
    await _lsp.restartLanguage(languageId);
    notifyListeners();
  }

  /// Format [path] against the latest [text] and return edits for the buffer.
  ///
  /// Flushes a full `didChange` first. An empty list means no server, no
  /// formatting support, or an LSP failure.
  Future<List<LspTextEdit>> lspFormat(String path, String text) async {
    await _lsp.changeDocument(path: path, text: text);
    return _lsp.formatDocument(path);
  }

  // ---- File mutations (create, rename, delete) ------------------------------

  /// Create and optionally open an empty file below [dirPath].
  ///
  /// Returns a validation or filesystem failure for inline display. Success
  /// refreshes the file tree.
  Future<Result<void, String>> createFileIn(
    String dirPath,
    String name, {
    bool open = true,
  }) async {
    final checked = FileNameValidator.validate(dirPath, name);
    if (!checked.isValid) return Failure(checked.error!);
    final path = checked.path!;
    final r = await _fileMutator.createFile(path);
    if (r.isSuccess) {
      _bumpFileTree();
      if (open) await openFile(path);
    }
    return r;
  }

  /// Create a folder below [dirPath] and refresh the tree on success.
  Future<Result<void, String>> createDirIn(String dirPath, String name) async {
    final checked = FileNameValidator.validate(dirPath, name);
    if (!checked.isValid) return Failure(checked.error!);
    final r = await _fileMutator.createDirectory(checked.path!);
    if (r.isSuccess) _bumpFileTree();
    return r;
  }

  /// Rename [path] within its parent and retarget affected viewer tabs.
  Future<Result<void, String>> renamePath(String path, String newName) async {
    final checked = FileNameValidator.validate(_parentOf(path), newName);
    if (!checked.isValid) return Failure(checked.error!);
    final to = checked.path!;
    final r = await _fileMutator.rename(path, to);
    if (r.isSuccess) {
      await _retargetSessions(path, to);
      _bumpFileTree();
    }
    return r;
  }

  /// Close affected viewers and move [path] to the trash.
  ///
  /// Deletion takes precedence over unsaved-draft prompts.
  Future<Result<void, String>> deletePath(String path) async {
    _closeSessionsUnder(path);
    final r = await _fileMutator.moveToTrash(path);
    if (r.isSuccess) _bumpFileTree();
    return r;
  }

  void _bumpFileTree() {
    _fileTreeRevision++;
    notifyListeners();
  }

  String _parentOf(String path) {
    final i = max(path.lastIndexOf('/'), path.lastIndexOf(r'\'));
    return i <= 0 ? path : path.substring(0, i);
  }

  /// Report whether a path is [root] itself or one of its descendants.
  bool _isUnder(String path, String root) =>
      path == root || path.startsWith('$root/');

  /// Retarget viewers affected by a rename and reattach their file watchers.
  Future<void> _retargetSessions(String from, String to) =>
      _workspace.retargetViewersUnder(from, to);

  /// Close active-project viewers at or below [path].
  ///
  /// Collects pane-tab pairs before mutation so traversal remains stable.
  void _closeSessionsUnder(String path) {
    final tree = _activeTree;
    if (tree == null) return;
    final targets = <(String, String)>[];
    for (final leaf in leaves(tree)) {
      for (final tabId in leaf.tabs) {
        final s = _workspace.item(tabId);
        if (s is FileViewerSession && _isUnder(s.path, path)) {
          targets.add((leaf.id, tabId));
        }
      }
    }
    for (final (paneId, tabId) in targets) {
      closeTab(paneId, tabId);
    }
  }

  /// Return a project's pane tree for its `IndexedStack` child.
  PaneNode? tree(String projectId) => _documents[projectId]?.root;

  /// Return the focused pane id for a project.
  String? focusedPaneId(String projectId) =>
      _documents[projectId]?.focusedPaneId;

  /// Count completed agent turns not yet viewed in a workspace.
  int notificationCount(String projectId) => _workspace.items.where((item) {
    if (item is! AgentSession) return false;
    return item.projection.projectId == projectId && item.unseenFinish;
  }).length;

  // ---- Initialization -------------------------------------------------------

  /// Load projects and layouts, activate the initial selection, and start refreshes.
  ///
  /// Marks [ready] only after the selected workspace has been realized. Git,
  /// worktree, and application discovery continue asynchronously afterward.
  Future<void> init() async {
    try {
      _projectList.addAll(await _projects.all());
      // Load saved layouts without realizing their live resources yet.
      for (final project in _projectList) {
        _savedLayouts[project.id] = await _layoutStore.load(project.id);
      }
      _selectedProjectId = await _initialSelection();
      // Realize live resources only for the initially selected project.
      final selected = _selectedProjectId;
      try {
        if (selected != null) await _activateProject(selected);
        _startGitWatch(selected);
      } catch (error, stack) {
        _recordInitializationError(error);
        debugPrint('[boot] failed to activate the workspace: $error\\n$stack');
      }
      _recordTerminalRecovery(selected);
      // Refresh Git and worktrees asynchronously. Boot starts with roots only;
      // reconciliation adds forks as results arrive.
      for (final project in _projectList) {
        unawaited(_refreshGit(project.id));
        unawaited(_refreshWorktrees(project.id));
      }
      // Discover installed IDEs asynchronously and update the top bar on arrival.
      unawaited(
        _launcher.probe().then((apps) {
          _availableApps = apps;
          notifyListeners();
        }),
      );
    } catch (error, stack) {
      _recordInitializationError(error);
      debugPrint('[boot] failed to initialize Cockpit: $error\\n$stack');
    } finally {
      // CockpitPage starts init fire-and-forget. Readiness must converge even
      // when persistence, filesystem, or process restoration fails.
      _ready = true;
      notifyListeners();
    }
  }

  void _recordInitializationError(Object error) {
    _initializationError ??= error.toString();
  }

  void _recordTerminalRecovery(String? projectId) {
    if (projectId == null) return;
    for (final item in _workspace.itemsForProject(projectId)) {
      if (item is TerminalSession && item.startupError != null) {
        _recordInitializationError(item.startupError!);
      }
    }
  }

  /// Resolve the initial root workspace from the last selection or first root.
  ///
  /// Returns `null` when no root exists and silently falls back on read failure.
  Future<String?> _initialSelection() async {
    final roots = rootProjects;
    if (roots.isEmpty) return null;
    try {
      final last = await _projects.loadLastSelected();
      if (last != null && roots.any((p) => p.id == last)) return last;
    } catch (_) {
      // Fall back silently when the saved preference cannot be read.
    }
    return roots.first.id;
  }

  /// Open the selected project folder in [app], if a project is selected.
  Future<void> openProjectInApp(LaunchableApp app) async {
    final project = selectedProject;
    if (project == null) return;
    await _launcher.launch(app, project.path);
  }

  /// Open [path] with the operating system's default application.
  Future<void> openWithDefaultApp(String path) =>
      _launcher.openWithDefaultApp(path);

  // ---- Projects -------------------------------------------------------------

  /// Create or select a workspace for [path].
  ///
  /// Optional identity values override folder-derived defaults. A new project
  /// is persisted, activated, and scheduled for Git and worktree refresh.
  Future<Project> addProject(
    String path, {
    String? name,
    int? colorValue,
    String? imagePath,
  }) async {
    for (final existing in _projectList) {
      if (existing.path == path) {
        _selectedProjectId = existing.id;
        unawaited(_projects.saveLastSelected(existing.id));
        notifyListeners();
        return existing;
      }
    }
    final basename = _basename(path);
    final resolvedName = (name != null && name.trim().isNotEmpty)
        ? name.trim()
        : (basename.isEmpty ? path : basename);
    // Rotate colors by root count; worktrees do not consume palette slots.
    final roots = _projectList.where((p) => p.parentId == null);
    final rootCount = roots.length;
    // Append after the greatest persisted root order.
    final nextOrder = roots.isEmpty
        ? 0
        : roots.map((p) => p.order).reduce(max) + 1;
    final project = Project(
      id: path, // The path is unique and stable across restarts.
      name: resolvedName,
      path: path,
      colorValue: colorValue ?? _palette[rootCount % _palette.length],
      createdAt: DateTime.now(),
      order: nextOrder,
      imagePath: imagePath,
    );
    _projectList.add(project);
    _selectedProjectId = project.id;
    await _projects.save(project);
    unawaited(_projects.saveLastSelected(project.id));
    await _activateProject(project.id); // No layout produces an empty pane.
    unawaited(_refreshGit(project.id));
    unawaited(
      _refreshWorktrees(project.id),
    ); // Discover existing disk worktrees.
    notifyListeners();
    return project;
  }

  /// Update and persist project identity fields.
  ///
  /// [imagePath] defaults to [Project.unchanged]; pass `null` to remove the
  /// image or a path to replace it.
  Future<void> updateProject(
    String id, {
    String? name,
    int? colorValue,
    Object? imagePath = Project.unchanged,
  }) async {
    final index = _projectList.indexWhere((p) => p.id == id);
    if (index < 0) return;
    final updated = _projectList[index].copyWith(
      name: name,
      colorValue: colorValue,
      imagePath: imagePath,
    );
    _projectList[index] = updated;
    await _projects.save(updated);
    notifyListeners();
  }

  /// Reorder root workspaces around [targetId] and persist sequential order.
  ///
  /// Worktrees follow their parent during reconciliation.
  Future<void> reorderWorkspace(
    String movedId,
    String targetId, {
    required bool before,
  }) async {
    if (movedId == targetId) return;
    final roots = rootProjects.toList(); // Already sorted by persisted order.
    final from = roots.indexWhere((p) => p.id == movedId);
    if (from < 0 || roots.indexWhere((p) => p.id == targetId) < 0) return;
    final moved = roots.removeAt(from);
    var insertAt = roots.indexWhere((p) => p.id == targetId);
    if (!before) insertAt += 1;
    roots.insert(insertAt, moved);
    // Assign sequential order values and persist every root.
    for (var i = 0; i < roots.length; i++) {
      final updated = roots[i].copyWith(order: i);
      final idx = _projectList.indexWhere((p) => p.id == updated.id);
      if (idx >= 0) _projectList[idx] = updated;
      await _projects.save(updated);
    }
    notifyListeners();
  }

  /// Remove a workspace from local state and terminate all of its live resources.
  ///
  /// Its disk folder is preserved; associated worktree runtimes are also closed.
  Future<void> removeProject(String id) async {
    // Close worktree runtimes with their root so no live fork is orphaned.
    for (final fork in _worktrees.remove(id) ?? const <Project>[]) {
      await _disposeProjectRuntime(fork.id);
      _projectList.removeWhere((p) => p.id == fork.id);
    }
    await _disposeProjectRuntime(id);
    _projectList.removeWhere((p) => p.id == id);
    if (_selectedProjectId == id || _projectById(_selectedProjectId) == null) {
      _selectedProjectId = rootProjects.isEmpty ? null : rootProjects.first.id;
    }
    await _projects.remove(id);
    await _layoutStore.remove(id);
    final next = _selectedProjectId;
    if (next != null) await _activateProject(next);
    notifyListeners();
  }

  /// Dispose a project's pane tree, sessions, focus, and caches without persistence changes.
  Future<void> _disposeProjectRuntime(String id) async {
    final document = _documents.remove(id);
    _savedLayouts.remove(id);
    _gitInfo.remove(id);
    _gitTree.remove(id);
    _saveTimers.remove(id)?.cancel();
    if (document != null) {
      await _workspace.disposeProject(document);
    }
  }

  /// Create and select a worktree below [rootId].
  ///
  /// On success, reconciles Git state and returns the selected fork with a
  /// cloned layout. On failure, returns the Git error for inline display.
  Future<Result<Project, WorktreeOpError>> createWorktree(
    String rootId,
    String name,
  ) async {
    final root = _projectById(rootId);
    if (root == null) {
      return const Failure(WorktreeOpError('Workspace not found.'));
    }
    final res = await _worktreeMgr.add(root.path, name);
    switch (res) {
      case Failure(:final error):
        return Failure<Project, WorktreeOpError>(error);
      case Success(:final value):
        // Clone the parent's pane layout into the new folder with fresh sessions.
        final clonedLayout = _cloneLayoutForWorktree(rootId);
        await _refreshWorktrees(rootId); // Insert the fork into project state.
        final fork = _projectById(value.path);
        if (fork == null) {
          return const Failure(
            WorktreeOpError(
              'Worktree created, but did not appear in the list.',
            ),
          );
        }
        if (clonedLayout != null) {
          // Seed the fork's saved layout so activation rebuilds it at fork.path,
          // and persist it across application restarts.
          _savedLayouts[fork.id] = clonedLayout;
          unawaited(_layoutStore.save(fork.id, clonedLayout));
        }
        selectProject(
          fork.id,
        ); // Selection activates and realizes the cloned layout.
        return Success<Project, WorktreeOpError>(fork);
    }
  }

  /// Load local branches and worktrees for live creation-dialog validation.
  Future<WorktreeNamespace> worktreeNamespace(String rootId) async {
    final root = _projectById(rootId);
    if (root == null) return const WorktreeNamespace.empty();
    return _worktreeMgr.namespace(root.path);
  }

  /// Remove a worktree and its branch, then reconcile project runtime state.
  ///
  /// Successful reconciliation terminates its agents, closes panes, and moves
  /// selection to the parent. Failures preserve the Git error for inline display.
  Future<Result<void, WorktreeOpError>> removeWorktree(String forkId) async {
    final fork = _projectById(forkId);
    if (fork == null || fork.parentId == null) {
      return const Failure(WorktreeOpError('Worktree not found.'));
    }
    final root = _projectById(fork.parentId);
    if (root == null) {
      return const Failure(WorktreeOpError('Parent workspace not found.'));
    }
    final res = await _worktreeMgr.remove(root.path, fork.path, fork.name);
    if (res.isSuccess) {
      // Reconciliation observes its absence from `git worktree list` and owns
      // process teardown, pane closure, and parent reselection.
      await _refreshWorktrees(fork.parentId!);
    }
    return res;
  }

  /// Report whether a worktree branch is merged.
  ///
  /// Returns `false` on missing state or uncertainty so removal keeps the safer
  /// unmerged-work warning.
  Future<bool> isWorktreeBranchMerged(String forkId) async {
    final fork = _projectById(forkId);
    if (fork == null || fork.parentId == null) return false;
    final root = _projectById(fork.parentId);
    if (root == null) return false;
    return _worktreeMgr.isBranchMerged(root.path, fork.name);
  }

  /// Select and lazily activate a project, moving Git watchers and refreshes.
  void selectProject(String id) {
    if (_selectedProjectId == id) return;
    _selectedProjectId = id;
    // Persist the root workspace for selection on the next startup.
    unawaited(_projects.saveLastSelected(_rootOf(id)));
    _clearFocusedNotification();
    unawaited(_activateProject(id)); // Realize lazily when not already active.
    _startGitWatch(id); // Follow the newly selected working tree.
    unawaited(_refreshGit(id)); // Refresh changes since the previous selection.
    unawaited(
      _refreshWorktrees(_rootOf(id)),
    ); // Reflect external worktree changes.
    notifyListeners();
  }

  /// List subfolders below the selected project for agent working-directory selection.
  ///
  /// [relativePath] uses `/`, stays within the project root, and defaults to it.
  Future<List<String>> subfolders([String relativePath = '']) async {
    final project = selectedProject;
    if (project == null) return const <String>[];
    final base = relativePath.isEmpty
        ? project.path
        : '${project.path}/$relativePath';
    return _folders.subfolders(base);
  }

  /// List saved Pi sessions for a directory, newest first.
  Future<List<SessionInfo>> historyFor(String cwd) =>
      _history.sessionsFor(cwd, withTitle: true);

  /// Persist agent identity and relay settings.
  ///
  /// A live name change is also sent through the relay control channel.
  Future<void> saveAgentConfig(
    String sessionId, {
    required String agentName,
    required bool autoStartRelay,
  }) async {
    final s = _workspace.item(sessionId);
    if (s is! AgentSession) return;

    final nameChanged = agentName.trim() != s.title;
    final relayChanged = autoStartRelay != s.autoStartRelay;
    if (!nameChanged && !relayChanged) return;

    s.rename(agentName.trim());
    s.setAutoStartRelay(autoStartRelay);
    if (nameChanged && s.isAlive) {
      unawaited(s.sendRelayControl(PiControlCommand.rename(agentName)));
    }
    notifyListeners();
  }

  // ---- Agent, tab, and split operations for the active project --------------

  /// Focus a pane and clear any completion marker on its active tab.
  void focus(String paneId) {
    _applyWorkspaceCommand(
      (document) =>
          WorkspaceDocumentCommands.focusPane(document, paneId: paneId),
    );
  }

  /// Select a tab in [paneId] and make it the focused workspace target.
  void selectTab(String paneId, String agentId) {
    _applyWorkspaceCommand(
      (document) => WorkspaceDocumentCommands.selectTab(
        document,
        paneId: paneId,
        tabId: agentId,
      ),
    );
  }

  /// Append a "New" placeholder for later conversion by [fillEmpty].
  void newEmptyTab(String paneId) {
    final projectId = _selectedProjectId;
    final project = selectedProject;
    if (projectId == null || project == null) return;
    final empty = _makeEmpty(projectId);
    final applied = _applyWorkspaceCommand(
      (document) => WorkspaceDocumentCommands.appendTab(
        document,
        paneId: paneId,
        tab: _workspace.descriptorFor(empty, project),
      ),
    );
    if (!applied) ownAsync(_workspace.disposeTab(empty.id));
  }

  /// Create an agent or terminal directly in [subRelative] without a dialog.
  ///
  /// Replaces the active empty placeholder or appends and activates a new tab.
  void newTabIn(String subRelative, {required bool terminal}) {
    final document = _activeDocument;
    final project = selectedProject;
    if (document == null || project == null) return;
    final paneId = focusedPaneId(project.id) ?? leaves(document.root).first.id;
    final leaf = findLeaf(document.root, paneId) ?? leaves(document.root).first;
    final s = _spawn(subRelative, terminal: terminal);
    final tab = _workspace.descriptorFor(s, project);

    final active = _workspace.item(leaf.active);
    final replaceEmpty = active is AgentSession && active.isPlaceholder;

    final applied = _applyWorkspaceCommand(
      (doc) => replaceEmpty
          ? WorkspaceDocumentCommands.replaceTab(
              doc,
              paneId: leaf.id,
              oldTabId: leaf.active,
              newTab: tab,
            )
          : WorkspaceDocumentCommands.appendTab(doc, paneId: leaf.id, tab: tab),
    );
    if (!applied) ownAsync(_workspace.disposeTab(s.id));
  }

  /// Split a pane and create a matching agent or terminal beside it.
  void splitPane(String paneId, SplitDir dir, String subRelative) {
    final document = _activeDocument;
    final project = selectedProject;
    if (document == null || project == null) return;
    // Match the new pane to the active tab type: terminal or agent.
    final leaf = findLeaf(document.root, paneId);
    final active = leaf == null ? null : _workspace.item(leaf.active);
    final terminal = active is TerminalSession;
    final s = _spawn(subRelative, terminal: terminal);
    final applied = _applyWorkspaceCommand(
      (doc) => WorkspaceDocumentCommands.splitPane(
        doc,
        targetPaneId: paneId,
        dir: dir,
        tab: _workspace.descriptorFor(s, project),
        newPaneId: _nid('pane'),
        newSplitId: _nid('sp'),
      ),
    );
    if (!applied) ownAsync(_workspace.disposeTab(s.id));
  }

  // ---- Tab drag and drop ----------------------------------------------------

  /// Move [tabId] into [targetPaneId] without disposing its live session.
  void moveTabToPane(String srcPaneId, String tabId, String targetPaneId) {
    _applyWorkspaceCommand(
      (document) => WorkspaceDocumentCommands.moveTabToPane(
        document,
        srcPaneId: srcPaneId,
        tabId: tabId,
        targetPaneId: targetPaneId,
      ),
    );
  }

  /// Move [tabId] into a new split beside [targetPaneId].
  ///
  /// [before] places the new pane left/above rather than right/below. The live
  /// session is moved, not disposed.
  void moveTabToNewSplit(
    String srcPaneId,
    String tabId,
    String targetPaneId,
    SplitDir dir, {
    required bool before,
  }) {
    _applyWorkspaceCommand(
      (document) => WorkspaceDocumentCommands.moveTabToNewSplit(
        document,
        srcPaneId: srcPaneId,
        tabId: tabId,
        targetPaneId: targetPaneId,
        dir: dir,
        before: before,
        newPaneId: _nid('pane'),
        newSplitId: _nid('sp'),
      ),
    );
  }

  /// Reorder [tabId] within a pane or insert it at [index] in another pane.
  ///
  /// Moving the tab preserves its live session.
  void moveTabToIndex(
    String srcPaneId,
    String tabId,
    String targetPaneId,
    int index,
  ) {
    _applyWorkspaceCommand(
      (document) => WorkspaceDocumentCommands.moveTabToIndex(
        document,
        srcPaneId: srcPaneId,
        tabId: tabId,
        targetPaneId: targetPaneId,
        index: index,
      ),
    );
  }

  /// Replace an empty placeholder with a live agent or terminal.
  void fillEmpty(
    String paneId,
    String emptyId,
    String subRelative, {
    bool terminal = false,
  }) {
    final project = selectedProject;
    if (project == null) return;
    final s = _spawn(subRelative, terminal: terminal);
    final applied = _applyWorkspaceCommand(
      (document) => WorkspaceDocumentCommands.fillEmpty(
        document,
        paneId: paneId,
        emptyTabId: emptyId,
        replacement: _workspace.descriptorFor(s, project),
      ),
    );
    if (!applied) ownAsync(_workspace.disposeTab(s.id));
  }

  /// Close and dispose a tab, inserting an empty placeholder when required.
  void closeTab(String paneId, String agentId) {
    final projectId = _selectedProjectId;
    if (projectId == null) return;
    final empty = _emptyTabDescriptor(projectId);
    final applied = _applyWorkspaceCommand(
      (document) => WorkspaceDocumentCommands.closeTab(
        document,
        paneId: paneId,
        tabId: agentId,
        emptyTab: empty,
      ),
    );
    if (!applied || !(_activeDocument?.tabs.containsKey(empty.id) ?? false)) {
      ownAsync(_workspace.disposeTab(empty.id));
    }
  }

  /// Close a pane and dispose tabs removed by the workspace command.
  void closePane(String paneId) {
    final projectId = _selectedProjectId;
    if (projectId == null) return;
    final empty = _emptyTabDescriptor(projectId);
    final applied = _applyWorkspaceCommand(
      (document) => WorkspaceDocumentCommands.closePane(
        document,
        paneId: paneId,
        emptyTab: empty,
      ),
    );
    if (!applied || !(_activeDocument?.tabs.containsKey(empty.id) ?? false)) {
      ownAsync(_workspace.disposeTab(empty.id));
    }
  }

  /// Resize a split through the canonical workspace command reducer.
  void resizeSplit(String splitId, double frac) {
    _applyWorkspaceCommand(
      (document) => WorkspaceDocumentCommands.resizeSplit(
        document,
        splitId: splitId,
        frac: frac,
      ),
    );
  }

  /// Toggle project-rail visibility for the current window session.
  void toggleRail() {
    _railVisible = !_railVisible;
    notifyListeners();
  }

  /// Toggle file-tree visibility for the current window session.
  void toggleTree() {
    _treeVisible = !_treeVisible;
    notifyListeners();
  }

  // ---- helpers --------------------------------------------------------------
  Project? _projectById(String? id) {
    for (final project in _projectList) {
      if (project.id == id) return project;
    }
    return null;
  }

  /// Resolve the root workspace that owns [id], or [id] itself when already root.
  String _rootOf(String id) => _projectById(id)?.parentId ?? id;

  WorkspaceDocument? get _activeDocument =>
      _selectedProjectId == null ? null : _documents[_selectedProjectId];

  PaneNode? get _activeTree => _activeDocument?.root;

  void _setDocument(WorkspaceDocument document) {
    _documents[document.projectId] = document.ensureFocusValid();
  }

  bool _applyWorkspaceCommand(
    WorkspaceCommandResult Function(WorkspaceDocument document) command,
  ) {
    final document = _activeDocument;
    if (document == null) return false;
    final result = command(document);
    final changed =
        !identical(result.document, document) ||
        result.disposeTabIds.isNotEmpty;
    if (!changed) return false;
    _setDocument(result.document);
    for (final id in result.disposeTabIds) {
      ownAsync(_workspace.disposeTab(id));
    }
    _clearFocusedNotification();
    notifyListeners();
    return true;
  }

  void _initDocument(String projectId) {
    if (_documents.containsKey(projectId)) return;
    final empty = _emptyTabDescriptor(projectId);
    final leaf = LeafPane(id: _nid('pane'), tabs: [empty.id], active: empty.id);
    _setDocument(
      WorkspaceDocument(
        projectId: projectId,
        root: leaf,
        focusedPaneId: leaf.id,
        tabs: <String, WorkspaceTab>{empty.id: empty},
      ),
    );
  }

  PaneItem _spawn(String subRelative, {required bool terminal}) {
    final project = selectedProject!;
    final cwd = subRelative.isEmpty
        ? project.path
        : '${project.path}/$subRelative';
    final title = _sanitizeName(
      subRelative.isEmpty ? project.name : _basename(subRelative),
    );
    return terminal
        ? _workspace.createTerminal(
            id: _nid('t'),
            projectId: project.id,
            workingDirectory: cwd,
            title: title,
          )
        : _workspace.createAgent(
            id: _nid('a'),
            project: project,
            workingDirectory: cwd,
            title: title,
          );
  }

  // ---- Notifications --------------------------------------------------------

  /// Resolve the active tab id in the selected project's focused pane.
  String? get _focusedAgentId {
    final pid = _selectedProjectId;
    if (pid == null) return null;
    final document = _documents[pid];
    if (document == null) return null;
    final tree = document.root;
    final paneId = document.focusedPaneId;
    final leaf = findLeaf(tree, paneId);
    if (leaf != null) return leaf.active;
    final ls = leaves(tree);
    return ls.isEmpty ? null : ls.first.active;
  }

  void _onAgentTurnEnd(AgentSession session) {
    if (session.sessionPath == null) {
      unawaited(_workspace.captureSessionPath(session));
    }
    unawaited(_refreshGit(session.projectId));
    unawaited(_refreshWorktrees(_rootOf(session.projectId)));
    unawaited(
      _workspace.notifyIfNeeded(
        session,
        isActiveTab: session.id == _focusedAgentId,
        notificationsEnabled: _notificationsEnabled,
        workspace: _projectById(session.projectId)?.name ?? '',
      ),
    );
  }

  /// Clear the unseen marker on the tab that just became focused.
  void _clearFocusedNotification() {
    final id = _focusedAgentId;
    if (id != null) _workspace.clearUnseen(id);
  }

  AgentSession _makeEmpty(String projectId) =>
      _workspace.createEmpty(id: _nid('a'), projectId: projectId);

  WorkspaceTab _emptyTabDescriptor(String projectId) {
    final id = _nid('a');
    _workspace.createEmpty(id: id, projectId: projectId);
    return WorkspaceTab.empty(id: id);
  }

  // ---- Layout persistence --------------------------------------------------

  /// Lazily realize a project's pane tree and live resources.
  ///
  /// A missing layout creates one empty pane. Activation is idempotent.
  Future<void> _activateProject(String id) async {
    if (_documents.containsKey(id)) return;
    final doc = _savedLayouts[id];
    if (doc == null) {
      _initDocument(id); // Synchronously create the default empty pane.
      return;
    }
    _restoring = true;
    try {
      await _restoreProject(id, doc);
    } finally {
      _restoring = false;
    }
    notifyListeners();
  }

  Future<void> _restoreProject(String id, Map<String, dynamic> doc) async {
    final project = _projectById(id);
    if (project == null) {
      _initDocument(id);
      return;
    }
    var document = WorkspaceDocument.fromPersistedJson(
      projectId: id,
      json: doc,
    );
    _bumpSeqPast(document.tabs.keys, document.root);

    final restored = <String>{};
    for (final tab in document.tabs.values) {
      try {
        if (await _workspace.realize(tab, project)) restored.add(tab.id);
      } catch (error, stack) {
        _recordInitializationError(error);
        debugPrint(
          '[restore] failed to restore tab ${tab.id}: $error\\n$stack',
        );
      }
    }

    document = document.filterTabs(
      restored,
      emptyTabFactory: () => _emptyTabDescriptor(project.id),
    );
    _setDocument(document);
  }

  /// Advance `_seq` beyond restored numeric suffixes to prevent id collisions.
  void _bumpSeqPast(Iterable<String> sessionIds, PaneNode tree) {
    var maxN = _seq;
    void scan(String id) {
      final m = RegExp(r'(\d+)$').firstMatch(id);
      if (m != null) maxN = max(maxN, int.parse(m.group(1)!) + 1);
    }

    sessionIds.forEach(scan);
    void walk(PaneNode n) {
      scan(n.id);
      switch (n) {
        case LeafPane():
          n.tabs.forEach(scan);
        case SplitPane():
          walk(n.a);
          walk(n.b);
      }
    }

    walk(tree);
    _seq = maxN;
  }

  Map<String, dynamic> _serializeLayout(String projectId) {
    final document = _documents[projectId];
    if (document == null) return const <String, dynamic>{};
    final refreshed = _documentWithLiveTabs(projectId, document);
    _setDocument(refreshed);
    return refreshed.toPersistedJson();
  }

  WorkspaceDocument _documentWithLiveTabs(
    String projectId,
    WorkspaceDocument document,
  ) {
    final project = _projectById(projectId);
    return project == null
        ? document
        : _workspace.documentWithLiveTabs(project, document);
  }

  /// Clone a root layout for a new worktree using fresh ids and sessions.
  ///
  /// Preserves split geometry and relative agent or terminal paths, removes
  /// session paths and viewers, and returns `null` when no usable tabs remain.
  Map<String, dynamic>? _cloneLayoutForWorktree(String rootId) {
    final doc = _documents.containsKey(rootId)
        ? _serializeLayout(rootId)
        : _savedLayouts[rootId];
    if (doc == null || doc.isEmpty) return null;
    final treeJson = doc['tree'];
    final sessionsJson = doc['sessions'];
    if (treeJson is! Map || sessionsJson is! Map) return null;

    // 1. Remap sessions with fresh type-specific ids, omitting viewers and paths.
    final tabIdMap = <String, String>{};
    final newSessions = <String, dynamic>{};
    for (final entry in sessionsJson.entries) {
      final desc = Map<String, dynamic>.from(entry.value as Map);
      if (desc['type'] == 'viewer') continue; // Worktrees do not clone viewers.
      desc.remove('sessionPath'); // Start a fresh agent conversation.
      final newId = _nid(desc['type'] == 'terminal' ? 't' : 'a');
      tabIdMap[entry.key as String] = newId;
      newSessions[newId] = desc;
    }
    if (newSessions.isEmpty) return null;

    // 2. Remap leaf and split ids, resolving tabs through tabIdMap.
    final nodeIdMap = <String, String>{};
    final newTree = _remapTreeForClone(
      paneNodeFromJson(treeJson.cast<String, dynamic>()),
      tabIdMap,
      nodeIdMap,
    );
    final focused = doc['focused'];
    return <String, dynamic>{
      'v': 1,
      'focused': focused is String ? nodeIdMap[focused] : null,
      'tree': paneNodeToJson(newTree),
      'sessions': newSessions,
    };
  }

  PaneNode _remapTreeForClone(
    PaneNode node,
    Map<String, String> tabIdMap,
    Map<String, String> nodeIdMap,
  ) {
    switch (node) {
      case LeafPane():
        final newId = nodeIdMap.putIfAbsent(node.id, () => _nid('pane'));
        final tabs = <String>[
          for (final t in node.tabs)
            if (tabIdMap[t] != null) tabIdMap[t]!,
        ];
        // A viewer-only leaf stays empty until restore sanitization inserts a
        // placeholder; `active` is only a harmless fallback in that case.
        final active =
            tabIdMap[node.active] ?? (tabs.isNotEmpty ? tabs.first : newId);
        return LeafPane(id: newId, tabs: tabs, active: active);
      case SplitPane():
        final newId = nodeIdMap.putIfAbsent(node.id, () => _nid('sp'));
        return SplitPane(
          id: newId,
          dir: node.dir,
          frac: node.frac,
          a: _remapTreeForClone(node.a, tabIdMap, nodeIdMap),
          b: _remapTreeForClone(node.b, tabIdMap, nodeIdMap),
        );
    }
  }

  /// Return [cwd] relative to project [root] using canonical `/` separators.
  ///
  /// Normalizing Windows separators before comparison preserves subfolder
  /// placement when Git and internal paths use different separator styles.
  String _subOf(String cwd, String root) {
    final c = cwd.replaceAll('\\', '/');
    final r = root.replaceAll('\\', '/');
    if (c == r) return '';
    final prefix = r.endsWith('/') ? r : '$r/';
    return c.startsWith(prefix) ? c.substring(prefix.length) : '';
  }

  void _scheduleSave(String projectId) {
    _saveTimers[projectId]?.cancel();
    _saveTimers[projectId] = Timer(const Duration(milliseconds: 500), () {
      _saveTimers.remove(projectId);
      final doc = _serializeLayout(projectId);
      if (doc.isNotEmpty) unawaited(_layoutStore.save(projectId, doc));
    });
  }

  /// Refresh a project's Git state after boot, selection, or an agent turn.
  Future<void> _refreshGit(String projectId) async {
    final project = _projectById(projectId);
    if (project == null) return;
    final info = await _gitReader.read(project.path);
    // Avoid rebuilding when branch, divergence, and file status are unchanged.
    final old = _gitInfo[projectId];
    if (old == info) {
      _gitInfo[projectId] =
          info; // Retain the key even without a visible change.
      return;
    }
    _gitInfo[projectId] = info;
    _gitTree[projectId] = _buildGitTree(info?.files);
    notifyListeners();
  }

  /// Expand file statuses into ancestor folders using the strongest descendant.
  static Map<String, GitFileStatus> _buildGitTree(
    Map<String, GitFileStatus>? files,
  ) {
    if (files == null || files.isEmpty) return const <String, GitFileStatus>{};
    final tree = <String, GitFileStatus>{};
    for (final entry in files.entries) {
      final path = entry.key; // Project-relative path with `/` separators.
      tree[path] = GitFileStatus.strongest(tree[path], entry.value)!;
      // Propagate `a/b/c.dart` to ancestor entries `a/b` and `a`.
      var slash = path.lastIndexOf('/');
      while (slash > 0) {
        final dir = path.substring(0, slash);
        tree[dir] = GitFileStatus.strongest(tree[dir], entry.value)!;
        slash = dir.lastIndexOf('/');
      }
    }
    return tree;
  }

  /// Move the filesystem watcher to the selected project's working tree.
  ///
  /// Keeps file and branch state live as agents edit, switch branches, or
  /// commit. Reusing the same path is a no-op.
  void _startGitWatch(String? projectId) {
    final path = projectId == null ? null : _projectById(projectId)?.path;
    if (path == _gitWatchPath) return; // This project is already watched.
    _gitWatch?.cancel();
    _gitWatchDebounce?.cancel();
    _gitWatch = null;
    _gitWatchPath = path;
    if (path == null || projectId == null) return;
    try {
      _gitWatch = Directory(path)
          .watch(recursive: true)
          .listen((event) => _onGitFsEvent(projectId, event));
    } catch (_) {
      _gitWatchPath = null; // Inaccessible folders fall back to manual refresh.
    }
  }

  /// Filter internal `.git` watcher noise and debounce meaningful changes.
  ///
  /// `HEAD` and `index` remain visible because they signal checkout, commit,
  /// or staging changes.
  void _onGitFsEvent(String projectId, FileSystemEvent event) {
    final p = event.path.replaceAll('\\', '/');
    final gitIdx = p.indexOf('/.git/');
    if (gitIdx != -1) {
      final rest = p.substring(gitIdx + 6); // Portion after `/.git/`.
      if (rest != 'HEAD' && rest != 'index') return;
    }
    _gitWatchDebounce?.cancel();
    _gitWatchDebounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(_refreshGit(projectId));
    });
  }

  /// Reconcile a root workspace's worktrees against Git.
  ///
  /// Adds new forks to project state, disposes missing fork runtimes, and moves
  /// selection back to the parent when necessary. Notifies only on change.
  Future<void> _refreshWorktrees(String rootId) async {
    final root = _projectById(rootId);
    if (root == null || root.parentId != null) return;

    final wts = await _worktreeMgr.list(root.path);
    final forks = <Project>[
      for (final Worktree w in wts)
        Project(
          id: w.path, // The path is the fork's stable id.
          name: w.branch,
          path: w.path,
          colorValue: root.colorValue,
          createdAt: root.createdAt,
          parentId: rootId,
          order: root.order, // Keep the fork nested with its parent.
        ),
    ];

    final old = _worktrees[rootId] ?? const <Project>[];
    final oldSig = old.map((f) => '${f.id}|${f.name}').toList();
    final newSig = forks.map((f) => '${f.id}|${f.name}').toList();
    final newIds = forks.map((f) => f.id).toSet();
    final oldIds = old.map((f) => f.id).toSet();

    // Dispose missing forks and remove them from project state.
    var switched = false;
    for (final gone in old.where((f) => !newIds.contains(f.id))) {
      await _disposeProjectRuntime(gone.id);
      _projectList.removeWhere((p) => p.id == gone.id);
      if (_selectedProjectId == gone.id) {
        _selectedProjectId = rootId; // Return selection to the parent.
        switched = true;
      }
    }
    // Add new forks and load any saved layout.
    for (final fresh in forks.where((f) => !oldIds.contains(f.id))) {
      _projectList.add(fresh);
      _savedLayouts[fresh.id] = await _layoutStore.load(fresh.id);
    }
    _worktrees[rootId] = forks;

    // Refresh each fork's dirty state independently.
    for (final f in forks) {
      unawaited(_refreshGit(f.id));
    }

    if (switched) await _activateProject(_selectedProjectId!);
    if (switched || !listEquals(oldSig, newSig)) notifyListeners();
  }

  String _basename(String path) {
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    return parts.isEmpty ? path : parts.last;
  }

  String _sanitizeName(String name) => name.replaceAll(' ', '-');

  /// Notify listeners and debounce persistence after structural changes.
  ///
  /// Persistence is skipped while a partially restored layout is active.
  @override
  void notifyListeners() {
    super.notifyListeners();
    if (_restoring) return;
    final id = _selectedProjectId;
    if (id != null && _documents.containsKey(id)) _scheduleSave(id);
  }

  @override
  void dispose() {
    _gitWatch?.cancel();
    _gitWatchDebounce?.cancel();
    for (final t in _saveTimers.values) {
      t.cancel();
    }
    _saveTimers.clear();
    ownAsync(_workspace.dispose());
    super.dispose();
  }
}
