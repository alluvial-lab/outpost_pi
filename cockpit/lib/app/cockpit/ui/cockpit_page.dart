import 'dart:async' show StreamSubscription, unawaited;

import 'package:cockpit/app/core/app_intents.dart';
import 'package:cockpit/app/cockpit/domain/entities/project.dart';
import 'package:cockpit/app/core/routes.dart';
import 'package:cockpit/app/cockpit/ui/session/agent_session.dart';
import 'package:cockpit/app/cockpit/ui/states/pane_node.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/update_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/widgets/widgets.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:flutter_modular/flutter_modular.dart';

/// Compose the Cockpit shell from its top bar, project rail, and split tree.
///
/// Each leaf renders a tabbed [PaneView] for agents, terminals, or files.
class CockpitPage extends StatefulWidget {
  const CockpitPage({super.key});

  @override
  State<CockpitPage> createState() => _CockpitPageState();
}

class _CockpitPageState extends State<CockpitPage> {
  CockpitViewModel get _vm => context.read<CockpitViewModel>();

  /// Keep draggable side-panel widths for this window session only.
  double _treeWidth = 300;
  static const double _treeMin = 220;
  static const double _treeMax = 620;

  double _railWidth = 252;
  static const double _railMin = 190;
  static const double _railMax = 420;

  @override
  void initState() {
    super.initState();
    // Bridge the global Command-L handler to the focused agent's composer,
    // including when focus has fallen onto empty shell space.
    requestFocusActiveComposer = _focusActiveComposer;
    // Start page-scoped ViewModels when the route mounts. Modules provide them
    // with `.new`, so factories do not chain `..init()` or `..check()`.
    context.read<CockpitViewModel>().init();
    context.read<UpdateViewModel>().check();
    // Keep LSP command overrides from the Language settings synchronized with
    // the pool initially and after every settings change.
    _settings = context.read<SettingsController>()
      ..addListener(_syncLspCommands)
      ..addListener(_syncNotifications);
    _syncLspCommands();
    _syncNotifications();
  }

  SettingsController? _settings;
  Map<String, String> _lastLspCommands = const <String, String>{};

  /// Mirror the app-scoped notification setting into the page-scoped ViewModel.
  ///
  /// The value gates end-of-turn notifications across the scope boundary.
  void _syncNotifications() {
    _vm.setNotificationsEnabled(_settings!.settings.notificationsEnabled);
  }

  void _syncLspCommands() {
    final next = _settings!.settings.lspCommands;
    _vm.applyLspCommands(next);
    // Restart languages whose command changed so live servers adopt it. The
    // first synchronization has no previous commands to restart.
    final langs = <String>{..._lastLspCommands.keys, ...next.keys};
    for (final id in langs) {
      if (_lastLspCommands[id] != next[id]) {
        unawaited(_vm.restartLspLanguage(id));
      }
    }
    _lastLspCommands = Map<String, String>.of(next);
  }

  @override
  void dispose() {
    _settings?.removeListener(_syncLspCommands);
    _settings?.removeListener(_syncNotifications);
    if (requestFocusActiveComposer == _focusActiveComposer) {
      requestFocusActiveComposer = null;
    }
    super.dispose();
  }

  /// Focus the active agent's composer, or do nothing for another tab type.
  void _focusActiveComposer() {
    final agent = _vm.focusedAgent;
    if (agent is AgentSession) agent.requestComposerFocus?.call();
  }

  /// Ensure a project is selected, prompting for a folder when necessary.
  ///
  /// Returns `true` once a project is ready for use.
  Future<bool> _ensureProject() async {
    if (_vm.selectedProject != null) return true;
    return _addProject();
  }

  Future<bool> _addProject() async {
    final vm = _vm;
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose the project folder',
    );
    if (path == null) return false;
    await vm.addProject(path);
    return true;
  }

  /// Run the Create Workspace flow with editable folder-derived defaults.
  Future<bool> _createWorkspace() async {
    final vm = _vm;
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose the workspace folder',
    );
    if (path == null || !mounted) return false;
    final suggestedName = path.split('/').where((p) => p.isNotEmpty).lastOrNull;
    final suggestedColor =
        kWorkspacePalette[vm.rootProjects.length % kWorkspacePalette.length];
    final result = await showWorkspaceSettingsDialog(
      context,
      name: suggestedName ?? path,
      colorValue: suggestedColor,
      path: path,
    );
    if (result == null) return false;
    await vm.addProject(
      path,
      name: result.name,
      colorValue: result.colorValue,
      imagePath: result.imagePath,
    );
    return true;
  }

  /// Edit workspace identity and explain when a rename reaches running agents.
  Future<void> _configureProject(Project project) async {
    final vm = _vm;
    final result = await showWorkspaceSettingsDialog(
      context,
      name: project.name,
      colorValue: project.colorValue,
      path: project.path,
      imagePath: project.imagePath,
    );
    if (result == null) return;
    await vm.updateProject(
      project.id,
      name: result.name,
      colorValue: result.colorValue,
      imagePath: result.imagePath,
    );
    if (!mounted) return;
    if (result.name != project.name) {
      await showInfoDialog(
        context,
        title: 'Workspace renamed',
        message:
            'The new name "${result.name}" will only be sent to agents '
            'after restarting the workspace or the application.',
      );
    }
  }

  /// Open worktree creation with live branch and worktree name validation.
  ///
  /// The dialog runs `git worktree add` through `onCreate`; the ViewModel then
  /// selects the new fork.
  Future<void> _createWorktree(Project root) async {
    final vm = _vm;
    final namespace = await vm.worktreeNamespace(root.id);
    if (!mounted) return;
    await showWorktreeCreateDialog(
      context,
      rootName: root.name,
      namespace: namespace,
      onCreate: (name) async {
        final res = await vm.createWorktree(root.id, name);
        return res.fold((_) => null, (e) => e.message);
      },
    );
  }

  /// Confirm and close a workspace without deleting its folder from disk.
  Future<void> _deleteProject(Project project) async {
    final vm = _vm;
    final ok = await showConfirmDialog(
      context,
      title: 'Close workspace',
      message:
          'Close "${project.name}"? The agents in this workspace will be '
          'terminated. The folder on disk is kept.',
      confirmLabel: 'Close',
      danger: true,
    );
    if (!ok) return;
    await vm.removeProject(project.id);
  }

  /// Confirm and remove a worktree, warning when its branch is unmerged.
  ///
  /// Removal deletes the worktree and branch, terminates fork agents, and
  /// returns selection to the parent. Git failures are shown in an info dialog.
  Future<void> _removeWorktree(Project fork) async {
    final vm = _vm;
    final merged = await vm.isWorktreeBranchMerged(fork.id);
    if (!mounted) return;
    final warn = merged
        ? ''
        : '\n\nWarning: the branch "${fork.name}" has not been merged yet — '
              'removing it (git branch -D) discards the unmerged work.';
    final ok = await showConfirmDialog(
      context,
      title: 'Remove worktree',
      message:
          'Remove "${fork.name}"? The worktree folder and the branch will be '
          'deleted and the agents in this fork will be terminated.$warn',
      confirmLabel: 'Remove',
      danger: true,
    );
    if (!ok) return;
    final res = await vm.removeWorktree(fork.id);
    if (!mounted) return;
    final err = res.fold<String?>((_) => null, (e) => e.message);
    if (err != null) {
      await showInfoDialog(
        context,
        title: 'Failed to remove worktree',
        message: err,
      );
    }
  }

  /// Ask where the agent should work and invoke [action] with a relative path.
  ///
  /// An empty path represents the project root.
  Future<void> _pickSubfolderThen(void Function(String sub) action) async {
    final vm = _vm;
    if (!await _ensureProject()) return;
    if (!mounted) return;
    final project = vm.selectedProject;
    if (project == null) return;
    final chosen = await showSubfolderDialog(
      context,
      projectName: project.name,
      loadSubfolders: vm.subfolders,
    );
    if (chosen == null) return;
    action(chosen);
  }

  /// Choose a saved Pi session for the active agent and replace its transcript.
  Future<void> _openHistory(String agentId) async {
    final vm = _vm;
    final session = vm.session(agentId);
    // History switching requires a live agent process.
    if (session is! AgentSession || !session.isAlive) return;
    final sessions = await vm.historyFor(session.workingDirectory);
    if (!mounted) return;
    final picked = await showHistoryDialog(context, sessions: sessions);
    if (picked == null) return;
    await session.loadHistory(picked.path);
  }

  void _renameAgent(String agentId, String name) {
    final vm = _vm;
    final session = vm.session(agentId);
    if (session is! AgentSession) return;
    unawaited(
      vm.saveAgentConfig(
        agentId,
        agentName: name,
        autoStartRelay: session.autoStartRelay,
      ),
    );
  }

  void _toggleRelayAgent(String agentId) {
    final vm = _vm;
    final session = vm.session(agentId);
    if (session is! AgentSession) return;
    unawaited(
      vm.saveAgentConfig(
        agentId,
        agentName: session.title,
        autoStartRelay: !session.autoStartRelay,
      ),
    );
  }

  /// Bind Command-L on macOS and Ctrl-L elsewhere to the focused composer.
  ///
  /// When focus is outside the shell, the global bridge in `main.dart` invokes
  /// [requestFocusActiveComposer] instead.
  Map<ShortcutActivator, VoidCallback> _focusComposerBindings() =>
      <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyL, meta: true):
            _focusActiveComposer,
        const SingleActivator(LogicalKeyboardKey.keyL, control: true):
            _focusActiveComposer,
      };

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CockpitViewModel>();
    final colors = context.colors;

    if (!vm.ready) {
      return Scaffold(
        backgroundColor: colors.bg,
        child: const Center(child: CircularProgressIndicator(size: 20)),
      );
    }

    return CallbackShortcuts(
      bindings: _focusComposerBindings(),
      // Keep the page in the focus chain before the first click so Command-L
      // works for a newly opened agent with no focused child.
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: colors.bg,
          child: Column(
            children: [
              if (vm.initializationError != null)
                _InitializationErrorBanner(message: vm.initializationError!),
              CockpitTopbar(
                projectName: vm.selectedDisplayTitle ?? 'Cockpit',
                railVisible: vm.railVisible,
                treeVisible: vm.treeVisible,
                openEnabled: vm.selectedProject != null,
                onToggleRail: vm.toggleRail,
                onToggleTree: vm.toggleTree,
                availableApps: vm.availableApps,
                lastOpenAppId: context.select<SettingsController, String?>(
                  (c) => c.settings.lastOpenAppId,
                ),
                onOpenInApp: (id) {
                  final app = vm.availableApps
                      .where((a) => a.id == id)
                      .firstOrNull;
                  if (app == null) return;
                  context.read<SettingsController>().setLastOpenApp(id);
                  unawaited(vm.openProjectInApp(app));
                },
              ),
              Expanded(
                child: Row(
                  children: [
                    if (vm.railVisible)
                      Stack(
                        children: [
                          ProjectsRail(
                            width: _railWidth,
                            projects: vm.rootProjects,
                            worktreesOf: vm.worktreesOf,
                            selectedId: vm.selectedProjectId,
                            notificationCount: vm.notificationCount,
                            gitInfo: vm.gitInfo,
                            onSelect: vm.selectProject,
                            onAdd: _createWorkspace,
                            onConfigure: _configureProject,
                            onDelete: _deleteProject,
                            onCreateWorktree: _createWorktree,
                            onRemoveWorktree: _removeWorktree,
                            onReorder: (moved, target, before) =>
                                vm.reorderWorkspace(
                                  moved,
                                  target,
                                  before: before,
                                ),
                            onOpenSettings: () =>
                                context.pushNamed(RoutePaths.settings),
                          ),
                          // Drag the right edge; moving right widens the rail.
                          Positioned(
                            right: 0,
                            top: 0,
                            bottom: 0,
                            child: _ResizeHandle(
                              onDelta: (dx) => setState(() {
                                _railWidth = (_railWidth + dx).clamp(
                                  _railMin,
                                  _railMax,
                                );
                              }),
                            ),
                          ),
                        ],
                      ),
                    Expanded(
                      child: vm.selectedProjectId == null
                          ? WelcomeView(onCreateWorkspace: _createWorkspace)
                          : IndexedStack(
                              index: _activeIndex(vm),
                              sizing: StackFit.expand,
                              children: [
                                // Keep one mounted multiplexer per project and
                                // paint only the active one to preserve state.
                                for (final project in vm.projects)
                                  KeyedSubtree(
                                    key: ValueKey(project.id),
                                    child: ColoredBox(
                                      color: colors.border,
                                      child: _multiplexer(vm, project.id),
                                    ),
                                  ),
                              ],
                            ),
                    ),
                    if (vm.treeVisible)
                      Stack(
                        children: [
                          FileTreePanel(
                            // Reset the file tree when the workspace root changes.
                            key: ValueKey(vm.selectedProject?.path ?? ''),
                            width: _treeWidth,
                            rootPath: vm.selectedProject?.path ?? '',
                            revision: vm.fileTreeRevision,
                            selectedPath: vm.selectedFileInTree,
                            listChildren: vm.listChildren,
                            gitStatusOf: vm.gitStatusForPath,
                            onOpenFile: (path) =>
                                vm.openFile(path, isPreview: false),
                            onTapFile:
                                vm.openFile, // A single click opens a preview.
                            onSelectFile: vm
                                .selectFileInTree, // Update the selection highlight.
                            onOpenWith: vm.openWithDefaultApp,
                            onCreateInFolder: (sub, terminal) =>
                                vm.newTabIn(sub, terminal: terminal),
                            onCreate: (parentDir, name, isFolder) => isFolder
                                ? vm.createDirIn(parentDir, name)
                                : vm.createFileIn(parentDir, name),
                            onRename: vm.renamePath,
                            onDelete: vm.deletePath,
                            footer: const _LspStatusBar(),
                          ),
                          // Drag the panel's left edge; moving left widens it.
                          Positioned(
                            left: 0,
                            top: 0,
                            bottom: 0,
                            child: _ResizeHandle(
                              onDelta: (dx) => setState(() {
                                _treeWidth = (_treeWidth - dx).clamp(
                                  _treeMin,
                                  _treeMax,
                                );
                              }),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _activeIndex(CockpitViewModel vm) {
    final index = vm.projects.indexWhere((p) => p.id == vm.selectedProjectId);
    return index < 0 ? 0 : index;
  }

  Widget _multiplexer(CockpitViewModel vm, String projectId) {
    final tree = vm.tree(projectId);
    if (tree == null) return const SizedBox.shrink();
    return _renderNode(vm, projectId, tree);
  }

  Widget _renderNode(CockpitViewModel vm, String projectId, PaneNode node) {
    if (node is LeafPane) {
      return PaneDropZone(
        key: ValueKey('drop-${node.id}'),
        paneId: node.id,
        vm: vm,
        child: PaneView(
          key: ValueKey(node.id),
          pane: node,
          vm: vm,
          focused: node.id == vm.focusedPaneId(projectId),
          onCreateTab: () => vm.newEmptyTab(node.id),
          onSplit: (dir) =>
              _pickSubfolderThen((sub) => vm.splitPane(node.id, dir, sub)),
          onFillEmpty: (emptyId, terminal) => _pickSubfolderThen(
            (sub) => vm.fillEmpty(node.id, emptyId, sub, terminal: terminal),
          ),
          onHistoryAgent: _openHistory,
          onRenameAgent: _renameAgent,
          onToggleRelayAgent: _toggleRelayAgent,
        ),
      );
    }
    final split = node as SplitPane;
    final isRow = split.dir == SplitDir.vertical;
    // Use a wide hit target while keeping the visual divider centered at 1 px.
    const handle = 12.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final total = isRow ? constraints.maxWidth : constraints.maxHeight;
        final aSize = total * split.frac;
        final bSize = total - aSize;
        final first = SizedBox(
          width: isRow ? aSize : null,
          height: isRow ? null : aSize,
          child: _renderNode(vm, projectId, split.a),
        );
        final second = SizedBox(
          width: isRow ? bSize : null,
          height: isRow ? null : bSize,
          child: _renderNode(vm, projectId, split.b),
        );
        final divider = PaneDivider(
          dir: split.dir,
          onDelta: (delta) {
            if (total <= 0) return;
            vm.resizeSplit(split.id, (aSize + delta) / total);
          },
        );
        return Stack(
          children: [
            // Lay out adjacent panes beneath the overlaid divider.
            isRow
                ? Row(children: [first, second])
                : Column(children: [first, second]),
            // Center the wide interactive handle on the visible divider.
            if (isRow)
              Positioned(
                left: aSize - handle / 2,
                width: handle,
                top: 0,
                bottom: 0,
                child: divider,
              )
            else
              Positioned(
                top: aSize - handle / 2,
                height: handle,
                left: 0,
                right: 0,
                child: divider,
              ),
          ],
        );
      },
    );
  }
}

/// Provide an 8 px drag target for resizing a side panel.
///
/// Keep workspace recovery visible while leaving the shell usable.
class _InitializationErrorBanner extends StatelessWidget {
  const _InitializationErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: colors.error.withValues(alpha: 0.12),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: colors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Workspace recovery issue: $message',
              style: context.typo.label.copyWith(color: colors.error),
            ),
          ),
        ],
      ),
    );
  }
}

/// The panel border supplies the visual line; the caller interprets the delta
/// direction according to whether this is a left or right edge.
class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({required this.onDelta});

  /// Report each horizontal drag delta in pixels.
  final ValueChanged<double> onDelta;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (d) => onDelta(d.delta.dx),
        child: const SizedBox(width: 8),
      ),
    );
  }
}

/// Show LSP status for the focused file tab in the Files pane footer.
///
/// The bar reports language and running state and offers restart. It keeps its
/// height when the focused tab is not supported so the layout does not jump,
/// and reacts to both tab changes and `lspStatusChanges`.
class _LspStatusBar extends StatefulWidget {
  const _LspStatusBar();

  @override
  State<_LspStatusBar> createState() => _LspStatusBarState();
}

class _LspStatusBarState extends State<_LspStatusBar> {
  StreamSubscription<void>? _sub;
  bool _restarting = false;

  @override
  void initState() {
    super.initState();
    _sub = context.read<CockpitViewModel>().lspStatusChanges.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _restart(CockpitViewModel vm) async {
    setState(() => _restarting = true);
    await vm.restartFocusedLsp();
    if (mounted) setState(() => _restarting = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final vm = context.watch<CockpitViewModel>();
    final status = vm.focusedLspStatus;

    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: status == null
          ? Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'No LSP available',
                style: context.typo.label.copyWith(color: colors.text4),
              ),
            )
          : Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: status.running
                        ? const Color(0xFF22C55E)
                        : colors.text4,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${status.label} LSP · ${status.running ? "running" : "stopped"}',
                    overflow: TextOverflow.ellipsis,
                    style: context.typo.label.copyWith(color: colors.text2),
                  ),
                ),
                Tooltip(
                  tooltip: (context) =>
                      const TooltipContainer(child: Text('Restart server')),
                  child: HoverTap(
                    borderRadius: BorderRadius.circular(6),
                    onTap: _restarting ? () {} : () => _restart(vm),
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: Icon(
                        Icons.refresh,
                        size: 15,
                        color: _restarting ? colors.text4 : colors.text2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
