import 'dart:io' show Platform;

import 'package:cockpit/app/cockpit/domain/entities/file_node.dart';
import 'package:cockpit/app/cockpit/domain/entities/git_file_status.dart';
import 'package:cockpit/app/cockpit/ui/widgets/confirm_dialog.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/core/ui/widgets/app_menu.dart';
import 'package:cockpit/app/core/ui/file_icons/file_icons.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Display and edit the selected workspace's lazily loaded file tree.
///
/// Folders start collapsed. Creation and renaming happen inline; deletion uses
/// the Trash on macOS and requires confirmation on other platforms.
class FileTreePanel extends StatefulWidget {
  const FileTreePanel({
    super.key,
    required this.rootPath,
    required this.revision,
    this.selectedPath,
    required this.listChildren,
    required this.gitStatusOf,
    required this.onOpenFile,
    this.onTapFile,
    this.onSelectFile,
    required this.onOpenWith,
    required this.onCreateInFolder,
    required this.onCreate,
    required this.onRename,
    required this.onDelete,
    this.width = 300,
    this.footer,
  });

  /// Optional footer pinned below the tree, such as an LSP status bar.
  final Widget? footer;

  final String rootPath;

  /// External mutation token that forces expanded folders to reload.
  final int revision;

  /// VM-owned path currently highlighted in the tree.
  final String? selectedPath;

  final Future<List<FileNode>> Function(String path) listChildren;

  /// Resolves Git status for an absolute path; `null` means clean or outside Git.
  final GitFileStatus? Function(String absolutePath) gitStatusOf;

  /// Opens a file in a pane after a double-click.
  final ValueChanged<String> onOpenFile;

  /// Opens a VS Code-style preview after a single click.
  final ValueChanged<String>? onTapFile;

  /// Selects and highlights a file after a single click.
  final ValueChanged<String>? onSelectFile;

  /// Opens the file or folder with the selected OS application.
  final ValueChanged<String> onOpenWith;

  /// Creates an agent or terminal tab from a folder's context menu.
  final void Function(String relativeSub, bool terminal) onCreateInFolder;

  /// Creates [name] in [parentDir], returning a displayable failure message.
  final Future<Result<void, String>> Function(
    String parentDir,
    String name,
    bool isFolder,
  )
  onCreate;

  /// Renames [path] to [newName] within the same parent folder.
  final Future<Result<void, String>> Function(String path, String newName)
  onRename;

  /// Moves [path] to the Trash after panel-owned confirmation when required.
  final Future<Result<void, String>> Function(String path) onDelete;

  /// Current page-controlled panel width; it is not persisted here.
  final double width;

  @override
  State<FileTreePanel> createState() => _FileTreePanelState();
}

/// Describe the single pending inline creation within [parentPath].
class _PendingCreate {
  const _PendingCreate(this.parentPath, this.isFolder);
  final String parentPath;
  final bool isFolder;
}

class _FileTreePanelState extends State<FileTreePanel> {
  int _localRefresh = 0;
  String? _selectedPath;

  /// The one inline creation currently in progress.
  _PendingCreate? _pending;

  /// Path currently being renamed inline, or `null`.
  String? _renaming;

  final FocusNode _treeFocus = FocusNode(debugLabel: 'fileTree');

  @override
  void dispose() {
    _treeFocus.dispose();
    super.dispose();
  }

  /// Combine monotonic manual and external revisions into one reload token.
  int get _refreshToken => _localRefresh + widget.revision;

  bool _isUnder(String path, String root) =>
      path == root || path.startsWith('$root/');

  void _select(String path) {
    setState(() => _selectedPath = path);
    _treeFocus.requestFocus();
  }

  // ---- inline creation ------------------------------------------------------

  void _startCreate(String parentPath, bool isFolder) {
    setState(() {
      _pending = _PendingCreate(parentPath, isFolder);
      _renaming = null;
    });
  }

  void _cancelCreate() {
    if (_pending != null) setState(() => _pending = null);
  }

  /// Commit an inline creation.
  ///
  /// Returns an error that keeps the input open, or `null` after success clears
  /// it; the VM revision then reloads the tree.
  Future<String?> _commitCreate(
    String parentPath,
    bool isFolder,
    String name,
  ) async {
    final r = await widget.onCreate(parentPath, name, isFolder);
    return r.fold((_) {
      if (mounted) setState(() => _pending = null);
      return null;
    }, (e) => e);
  }

  // ---- rename inline --------------------------------------------------------

  void _startRename(String path) {
    setState(() {
      _renaming = path;
      _pending = null;
    });
  }

  void _cancelRename() {
    if (_renaming != null) setState(() => _renaming = null);
  }

  Future<String?> _commitRename(String path, String newName) async {
    final r = await widget.onRename(path, newName);
    return r.fold((_) {
      if (mounted) {
        // Keep the selection attached to the renamed path.
        final parent = path.substring(0, path.lastIndexOf('/'));
        final newPath = '$parent/${newName.trim()}';
        setState(() {
          _renaming = null;
          if (_selectedPath != null && _isUnder(_selectedPath!, path)) {
            _selectedPath = newPath;
          }
        });
      }
      return null;
    }, (e) => e);
  }

  // ---- deletion -------------------------------------------------------------

  Future<void> _requestDelete(String path) async {
    final name = path.split('/').where((p) => p.isNotEmpty).last;
    // macOS uses the reversible Trash without confirmation, like Finder.
    // Other platforms delete permanently, so confirm first.
    if (!Platform.isMacOS) {
      final ok = await showConfirmDialog(
        context,
        title: 'Delete?',
        message: 'Permanently delete “$name”? This can’t be undone.',
        confirmLabel: 'Delete',
        danger: true,
      );
      if (!ok || !mounted) return;
    }
    final r = await widget.onDelete(path);
    if (!mounted) return;
    r.fold((_) {
      if (_selectedPath != null && _isUnder(_selectedPath!, path)) {
        setState(() => _selectedPath = null);
      }
    }, (e) => showInfoDialog(context, title: 'Could not delete', message: e));
  }

  // ---- keyboard shortcuts --------------------------------------------------

  bool get _editing => _pending != null || _renaming != null;

  void _renameSelected() {
    final p = _selectedPath;
    if (p != null && !_editing) _startRename(p);
  }

  void _deleteSelected() {
    final p = _selectedPath;
    if (p != null && !_editing) _requestDelete(p);
  }

  /// Handle tree shortcuts on the focused node instead of relying on bubbling.
  ///
  /// Delete or Backspace removes the selection; Enter on macOS or F2 elsewhere
  /// begins renaming it.
  KeyEventResult _onTreeKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _editing || _selectedPath == null) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final isDelete =
        key == LogicalKeyboardKey.delete ||
        (Platform.isMacOS && key == LogicalKeyboardKey.backspace);
    final isRename = Platform.isMacOS
        ? key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.numpadEnter
        : key == LogicalKeyboardKey.f2;
    if (isDelete) {
      _deleteSelected();
      return KeyEventResult.handled;
    }
    if (isRename) {
      _renameSelected();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // Prefer the VM selection when supplied, otherwise use local selection.
    final effectiveSelected = widget.selectedPath ?? _selectedPath;

    final edit = _TreeEdit(
      pending: _pending,
      renaming: _renaming,
      selectedPath: effectiveSelected,
      onSelect: _select,
      onOpenFile: widget.onOpenFile,
      onTapFile: widget.onTapFile,
      onSelectFile: widget.onSelectFile,
      onOpenWith: widget.onOpenWith,
      onCreateInFolder: widget.onCreateInFolder,
      onStartCreate: _startCreate,
      onCancelCreate: _cancelCreate,
      onCommitCreate: _commitCreate,
      onStartRename: _startRename,
      onCancelRename: _cancelRename,
      onCommitRename: _commitRename,
      onRequestDelete: _requestDelete,
      gitStatusOf: widget.gitStatusOf,
      listChildren: widget.listChildren,
    );

    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border(left: BorderSide(color: colors.border)),
      ),
      child: Column(
        children: [
          Container(
            height: 40,
            padding: const EdgeInsets.only(left: 14, right: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Row(
              children: [
                Icon(Icons.folder_outlined, size: 15, color: colors.text3),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Files',
                    overflow: TextOverflow.ellipsis,
                    style: context.typo.title.copyWith(
                      fontSize: 13,
                      color: colors.text,
                    ),
                  ),
                ),
                if (widget.rootPath.isNotEmpty) ...[
                  _HeaderIcon(
                    icon: Icons.note_add_outlined,
                    tooltip: 'New file',
                    onTap: () => _startCreate(widget.rootPath, false),
                  ),
                  _HeaderIcon(
                    icon: Icons.create_new_folder_outlined,
                    tooltip: 'New folder',
                    onTap: () => _startCreate(widget.rootPath, true),
                  ),
                ],
                _HeaderIcon(
                  icon: Icons.refresh,
                  tooltip: 'Refresh',
                  onTap: () => setState(() => _localRefresh++),
                ),
              ],
            ),
          ),
          Expanded(
            child: widget.rootPath.isEmpty
                ? Center(
                    child: Text(
                      'No folder — open a workspace.',
                      textAlign: TextAlign.center,
                      style: context.typo.label.copyWith(color: colors.text3),
                    ),
                  )
                : Focus(
                    focusNode: _treeFocus,
                    onKeyEvent: _onTreeKey,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 6,
                      ),
                      child: _DirView(
                        path: widget.rootPath,
                        rootPath: widget.rootPath,
                        depth: 0,
                        refreshToken: _refreshToken,
                        edit: edit,
                      ),
                    ),
                  ),
          ),
          ?widget.footer,
        ],
      ),
    );
  }
}

/// Bundle immutable tree-edit interactions to avoid threading many callbacks.
class _TreeEdit {
  const _TreeEdit({
    required this.pending,
    required this.renaming,
    required this.selectedPath,
    required this.onSelect,
    required this.onOpenFile,
    required this.onTapFile,
    required this.onSelectFile,
    required this.onOpenWith,
    required this.onCreateInFolder,
    required this.onStartCreate,
    required this.onCancelCreate,
    required this.onCommitCreate,
    required this.onStartRename,
    required this.onCancelRename,
    required this.onCommitRename,
    required this.onRequestDelete,
    required this.gitStatusOf,
    required this.listChildren,
  });

  final _PendingCreate? pending;
  final String? renaming;
  final String? selectedPath;

  final ValueChanged<String> onSelect;
  final ValueChanged<String> onOpenFile;
  final ValueChanged<String>? onTapFile;
  final ValueChanged<String>? onSelectFile;
  final ValueChanged<String> onOpenWith;
  final void Function(String relativeSub, bool terminal) onCreateInFolder;

  final void Function(String parentPath, bool isFolder) onStartCreate;
  final VoidCallback onCancelCreate;
  final Future<String?> Function(String parentPath, bool isFolder, String name)
  onCommitCreate;

  final ValueChanged<String> onStartRename;
  final VoidCallback onCancelRename;
  final Future<String?> Function(String path, String newName) onCommitRename;

  final ValueChanged<String> onRequestDelete;

  final GitFileStatus? Function(String absolutePath) gitStatusOf;
  final Future<List<FileNode>> Function(String path) listChildren;
}

/// Load and render a folder's children, reloading when [refreshToken] changes.
class _DirView extends StatefulWidget {
  const _DirView({
    required this.path,
    required this.rootPath,
    required this.depth,
    required this.refreshToken,
    required this.edit,
  });

  final String path;
  final String rootPath;
  final int depth;
  final int refreshToken;
  final _TreeEdit edit;

  @override
  State<_DirView> createState() => _DirViewState();
}

class _DirViewState extends State<_DirView> {
  List<FileNode>? _children;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_DirView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _load();
  }

  Future<void> _load() async {
    final children = await widget.edit.listChildren(widget.path);
    if (mounted) setState(() => _children = children);
  }

  @override
  Widget build(BuildContext context) {
    final children = _children;
    if (children == null) return const SizedBox.shrink();
    final edit = widget.edit;
    final pending = edit.pending;
    final showCreate = pending != null && pending.parentPath == widget.path;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Place inline creation at the top of its target folder.
        if (showCreate)
          _InlineEntry(
            key: ValueKey('create:${widget.path}:${pending.isFolder}'),
            depth: widget.depth,
            isFolder: pending.isFolder,
            onSubmit: (name) =>
                edit.onCommitCreate(widget.path, pending.isFolder, name),
            onCancel: edit.onCancelCreate,
          ),
        for (final node in children)
          if (node.isDirectory)
            _Folder(
              node: node,
              depth: widget.depth,
              refreshToken: widget.refreshToken,
              edit: edit,
            )
          else
            // Dragging a file into the composer turns it into `@<rel>`.
            Draggable<String>(
              data: node.path,
              dragAnchorStrategy: pointerDragAnchorStrategy,
              feedback: _FileChip(name: node.name),
              child: _Row(
                depth: widget.depth,
                isFolder: false,
                name: node.name,
                path: node.path,
                rootPath: widget.rootPath,
                selected: node.path == edit.selectedPath,
                renaming: edit.renaming == node.path,
                gitStatus: edit.gitStatusOf(node.path),
                onTap: () {
                  edit.onSelect(node.path);
                  edit.onSelectFile?.call(node.path);
                  edit.onTapFile?.call(node.path);
                },
                onDoubleTap: () => edit.onOpenFile(node.path),
                onOpenWith: () => edit.onOpenWith(node.path),
                onStartRename: () => edit.onStartRename(node.path),
                onCommitRename: (name) => edit.onCommitRename(node.path, name),
                onCancelRename: edit.onCancelRename,
                onDelete: () => edit.onRequestDelete(node.path),
              ),
            ),
      ],
    );
  }
}

class _Folder extends StatefulWidget {
  const _Folder({
    required this.node,
    required this.depth,
    required this.refreshToken,
    required this.edit,
  });

  final FileNode node;
  final int depth;
  final int refreshToken;
  final _TreeEdit edit;

  @override
  State<_Folder> createState() => _FolderState();
}

class _FolderState extends State<_Folder> {
  bool _expanded = false;

  /// Expand to reveal pending creation in this folder or a descendant.
  bool get _forceExpand {
    final p = widget.edit.pending;
    if (p == null) return false;
    final path = widget.node.path;
    return p.parentPath == path || p.parentPath.startsWith('$path/');
  }

  @override
  Widget build(BuildContext context) {
    final edit = widget.edit;
    final expanded = _expanded || _forceExpand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Row(
          depth: widget.depth,
          isFolder: true,
          expanded: expanded,
          name: widget.node.name,
          path: widget.node.path,
          rootPath: widget.node.path, // Not used for folders.
          selected: widget.node.path == edit.selectedPath,
          renaming: edit.renaming == widget.node.path,
          gitStatus: edit.gitStatusOf(widget.node.path),
          onCreateInFolder: edit.onCreateInFolder,
          onNewFile: () => edit.onStartCreate(widget.node.path, false),
          onNewFolder: () => edit.onStartCreate(widget.node.path, true),
          onOpenWith: () => edit.onOpenWith(widget.node.path),
          onStartRename: () => edit.onStartRename(widget.node.path),
          onCommitRename: (name) => edit.onCommitRename(widget.node.path, name),
          onCancelRename: edit.onCancelRename,
          onDelete: () => edit.onRequestDelete(widget.node.path),
          onTap: () {
            edit.onSelect(widget.node.path);
            setState(() => _expanded = !_expanded);
          },
        ),
        if (expanded)
          _DirView(
            path: widget.node.path,
            rootPath: widget.node.path,
            depth: widget.depth + 1,
            refreshToken: widget.refreshToken,
            edit: edit,
          ),
      ],
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({
    required this.depth,
    required this.isFolder,
    required this.name,
    required this.path,
    required this.rootPath,
    this.gitStatus,
    this.expanded = false,
    this.selected = false,
    this.renaming = false,
    this.onTap,
    this.onDoubleTap,
    this.onOpenWith,
    this.onCreateInFolder,
    this.onNewFile,
    this.onNewFolder,
    this.onStartRename,
    this.onCommitRename,
    this.onCancelRename,
    this.onDelete,
  });

  final int depth;
  final bool isFolder;
  final String name;
  final String path;
  final String rootPath;

  final GitFileStatus? gitStatus;
  final bool expanded;
  final bool selected;
  final bool renaming;

  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  /// Opens files with an app or reveals folders in the platform file explorer.
  final VoidCallback? onOpenWith;

  /// For folders, creates an agent or terminal at its relative path.
  final void Function(String relativeSub, bool terminal)? onCreateInFolder;

  /// For folders, begins inline file or folder creation.
  final VoidCallback? onNewFile;
  final VoidCallback? onNewFolder;

  final VoidCallback? onStartRename;
  final Future<String?> Function(String name)? onCommitRename;
  final VoidCallback? onCancelRename;
  final VoidCallback? onDelete;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  DateTime? _lastTap;

  String get _relative {
    final root = widget.rootPath.endsWith('/')
        ? widget.rootPath
        : '${widget.rootPath}/';
    return widget.path.startsWith(root)
        ? widget.path.substring(root.length)
        : widget.path;
  }

  void _handleTap() {
    if (widget.onDoubleTap == null) {
      widget.onTap?.call();
      return;
    }
    final now = DateTime.now();
    if (_lastTap != null && now.difference(_lastTap!).inMilliseconds < 350) {
      _lastTap = null;
      widget.onDoubleTap!();
    } else {
      _lastTap = now;
      widget.onTap?.call();
    }
  }

  String get _fileExplorerLabel {
    if (Platform.isMacOS) return 'Open in Finder';
    if (Platform.isWindows) return 'Open in Explorer';
    return 'Open in file manager';
  }

  void _showMenu(BuildContext context, Offset globalPosition) {
    final isFolder = widget.isFolder;
    final isFile = !isFolder;
    showAppMenu<String>(
      context,
      minWidth: 220,
      globalPosition: globalPosition,
      items: [
        if (isFile) ...const [
          AppMenuItem(value: 'open', label: 'Open', icon: Icons.open_in_new),
          AppMenuItem(
            value: 'openwith',
            label: 'Open with',
            icon: Icons.launch_outlined,
          ),
        ],
        if (isFolder) ...const [
          AppMenuItem(
            value: 'newfile',
            label: 'New file',
            icon: Icons.note_add_outlined,
          ),
          AppMenuItem(
            value: 'newfolder',
            label: 'New folder',
            icon: Icons.create_new_folder_outlined,
          ),
          AppMenuItem(
            value: 'agent',
            label: 'Create agent',
            icon: Icons.auto_awesome,
          ),
          AppMenuItem(
            value: 'terminal',
            label: 'Create terminal',
            icon: Icons.terminal_outlined,
          ),
        ],
        if (isFolder)
          AppMenuItem(
            value: 'reveal',
            label: _fileExplorerLabel,
            icon: Icons.folder_open_outlined,
          ),
        const AppMenuItem(
          value: 'rename',
          label: 'Rename',
          icon: Icons.drive_file_rename_outline,
        ),
        const AppMenuItem(
          value: 'delete',
          label: 'Delete',
          icon: Icons.delete_outline,
        ),
        const AppMenuItem(
          value: 'rel',
          label: 'Copy relative path',
          icon: Icons.content_copy_outlined,
        ),
        const AppMenuItem(
          value: 'abs',
          label: 'Copy absolute path',
          icon: Icons.content_copy,
        ),
      ],
    ).then((value) {
      switch (value) {
        case 'open':
          widget.onDoubleTap?.call();
        case 'openwith':
        case 'reveal':
          widget.onOpenWith?.call();
        case 'newfile':
          widget.onNewFile?.call();
        case 'newfolder':
          widget.onNewFolder?.call();
        case 'agent':
          widget.onCreateInFolder?.call(_relative, false);
        case 'terminal':
          widget.onCreateInFolder?.call(_relative, true);
        case 'rename':
          widget.onStartRename?.call();
        case 'delete':
          widget.onDelete?.call();
        case 'rel':
          Clipboard.setData(ClipboardData(text: _relative));
        case 'abs':
          Clipboard.setData(ClipboardData(text: widget.path));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final Widget label = widget.renaming
        ? _NameField(
            initial: widget.name,
            // Select a file's basename without its extension, as VS Code does.
            selectBasename: !widget.isFolder,
            onSubmit: (name) async =>
                await widget.onCommitRename?.call(name) ?? 'Rename failed.',
            onCancel: () => widget.onCancelRename?.call(),
          )
        : Text(
            widget.name,
            overflow: TextOverflow.ellipsis,
            style: context.typo.body.copyWith(
              fontSize: 13,
              color:
                  _gitColor(colors, widget.gitStatus) ??
                  (widget.selected ? colors.text : colors.text2),
            ),
          );

    final row = HoverTap(
      color: widget.selected ? colors.panel2 : Colors.transparent,
      hoverColor: colors.panel,
      borderRadius: BorderRadius.circular(5),
      onTap: widget.renaming ? null : _handleTap,
      padding: EdgeInsets.only(left: 6 + widget.depth * 14.0, right: 6),
      child: SizedBox(
        // Renaming grows the row to fit the field and error; otherwise it is fixed.
        height: widget.renaming ? null : 26,
        child: Row(
          children: [
            SizedBox(
              width: 14,
              child: widget.isFolder
                  ? Icon(
                      widget.expanded
                          ? Icons.keyboard_arrow_down
                          : Icons.chevron_right,
                      size: 15,
                      color: colors.text4,
                    )
                  : null,
            ),
            const SizedBox(width: 2),
            widget.isFolder
                ? FileTypeIcon.folder(
                    widget.name,
                    open: widget.expanded,
                    size: 16,
                  )
                : FileTypeIcon.file(widget.name, size: 16),
            const SizedBox(width: 7),
            Expanded(child: label),
          ],
        ),
      ),
    );

    // While renaming, let the field own selection and secondary gestures.
    if (widget.renaming) return row;
    return GestureDetector(
      onSecondaryTapUp: (d) => _showMenu(context, d.globalPosition),
      child: row,
    );
  }
}

/// Show inline creation as an icon and name field at the target tree depth.
class _InlineEntry extends StatelessWidget {
  const _InlineEntry({
    super.key,
    required this.depth,
    required this.isFolder,
    required this.onSubmit,
    required this.onCancel,
  });

  final int depth;
  final bool isFolder;
  final Future<String?> Function(String name) onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 6 + depth * 14.0, right: 6),
      child: Row(
        children: [
          const SizedBox(width: 14), // Align with folder chevrons.
          const SizedBox(width: 2),
          isFolder
              ? FileTypeIcon.folder('new', open: false, size: 16)
              : FileTypeIcon.file('new file', size: 16),
          const SizedBox(width: 7),
          Expanded(
            child: _NameField(
              initial: '',
              selectBasename: false,
              onSubmit: onSubmit,
              onCancel: onCancel,
            ),
          ),
        ],
      ),
    );
  }
}

/// Edit a created or renamed entry with shared keyboard and validation behavior.
///
/// The field autofocuses; Enter submits, while Escape or clicking outside
/// cancels. Validation errors appear below without releasing focus.
class _NameField extends StatefulWidget {
  const _NameField({
    required this.initial,
    required this.selectBasename,
    required this.onSubmit,
    required this.onCancel,
  });

  final String initial;

  /// Select only the basename when beginning a file rename.
  final bool selectBasename;

  /// Returns an error that keeps editing active, or `null` after success.
  final Future<String?> Function(String name) onSubmit;
  final VoidCallback onCancel;

  @override
  State<_NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<_NameField> {
  late final TextEditingController _ctrl;
  final FocusNode _focus = FocusNode();
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
    final dot = widget.initial.lastIndexOf('.');
    final end = (widget.selectBasename && dot > 0)
        ? dot
        : widget.initial.length;
    _ctrl.selection = TextSelection(baseOffset: 0, extentOffset: end);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final name = _ctrl.text.trim();
    if (name.isEmpty) {
      widget.onCancel();
      return;
    }
    setState(() => _busy = true);
    final err = await widget.onSubmit(name);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): widget.onCancel,
          },
          child: SizedBox(
            height: 22,
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              style: typo.body.copyWith(fontSize: 13, color: colors.text),
              border: Border.all(color: colors.accent),
              borderRadius: BorderRadius.circular(4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              onSubmitted: (_) => _submit(),
              onTapOutside: (_) => widget.onCancel(),
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 2),
            child: Text(
              _error!,
              style: typo.label.copyWith(fontSize: 11, color: colors.error),
            ),
          ),
      ],
    );
  }
}

/// Resolve the filename color for its Git status.
Color? _gitColor(AppColors colors, GitFileStatus? status) {
  switch (status) {
    case null:
      return null;
    case GitFileStatus.ignored:
      return colors.text4;
    case GitFileStatus.modified:
      return colors.warn;
    case GitFileStatus.staged:
      return colors.gitStaged;
    case GitFileStatus.untracked:
      return colors.gitUntracked;
    case GitFileStatus.deleted:
      return colors.gitDeleted;
    case GitFileStatus.conflict:
      return colors.gitConflict;
  }
}

class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      tooltip: (context) => TooltipContainer(child: Text(tooltip)),
      child: HoverTap(
        borderRadius: BorderRadius.circular(5),
        onTap: onTap,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(icon, size: 16, color: context.colors.text3),
        ),
      ),
    );
  }
}

/// Follow the cursor while dragging a file from the panel.
class _FileChip extends StatelessWidget {
  const _FileChip({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colors.panel2,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: colors.accent),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.alternate_email, size: 13, color: colors.accentText),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: context.typo.body.copyWith(
                fontSize: 12.5,
                color: colors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
