import 'dart:io';
import 'dart:math';

import 'package:cockpit/app/cockpit/domain/entities/agent_session_projection.dart';
import 'package:cockpit/app/cockpit/ui/session/agent_session.dart';
import 'package:cockpit/app/cockpit/ui/session/file_viewer_session.dart';
import 'package:cockpit/app/cockpit/ui/session/pane_item.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_session.dart';
import 'package:cockpit/app/cockpit/ui/states/pane_node.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/setup_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/widgets/agent_composer.dart';
import 'package:cockpit/app/cockpit/ui/widgets/agent_setup_checklist.dart';
import 'package:cockpit/app/cockpit/ui/widgets/agent_transcript.dart';
import 'package:cockpit/app/core/ui/widgets/app_menu.dart';
import 'package:cockpit/app/cockpit/ui/widgets/confirm_dialog.dart';
import 'package:cockpit/app/cockpit/ui/widgets/empty_pane.dart';
import 'package:cockpit/app/cockpit/ui/widgets/file_viewer.dart';
import 'package:cockpit/app/cockpit/ui/widgets/terminal_pane.dart';
import 'package:cockpit/app/core/ui/file_icons/file_icons.dart';
import 'package:cockpit/app/core/ui/themes/terminal_theme.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:xterm/xterm.dart';

/// Render one multiplexer leaf as a tab strip and its persistent tab bodies.
///
/// Only the active tab receives focus; agent, terminal, file, and empty-tab
/// content remain mounted according to their session contracts.
class PaneView extends StatelessWidget {
  const PaneView({
    super.key,
    required this.pane,
    required this.vm,
    required this.focused,
    required this.onCreateTab,
    required this.onSplit,
    required this.onFillEmpty,
    required this.onHistoryAgent,
    required this.onRenameAgent,
    required this.onToggleRelayAgent,
  });

  final LeafPane pane;
  final CockpitViewModel vm;
  final bool focused;

  /// Opens an empty New tab whose content type is selected inside the tab.
  final VoidCallback onCreateTab;
  final ValueChanged<SplitDir> onSplit;

  /// Replaces an empty tab, where `terminal` selects the new session type.
  final void Function(String emptyId, bool terminal) onFillEmpty;

  /// Opens an agent's session history by tab ID.
  final ValueChanged<String> onHistoryAgent;

  /// Renames an agent using its tab ID and an already sanitized name.
  final void Function(String agentId, String name) onRenameAgent;

  /// Toggles automatic relay startup for an agent tab.
  final ValueChanged<String> onToggleRelayAgent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tabs = pane.tabs;
    // Fall back to zero while the active tab is transiently absent during a move
    // or close.
    final rawIndex = tabs.indexOf(pane.active);
    final activeIndex = rawIndex < 0 ? 0 : rawIndex;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (_) => vm.focus(pane.id),
      child: Container(
        color: colors.panel,
        child: Column(
          children: [
            _TabStrip(
              pane: pane,
              vm: vm,
              focused: focused,
              onCreateTab: onCreateTab,
              onSplit: onSplit,
              onHistoryAgent: onHistoryAgent,
              onRenameAgent: onRenameAgent,
              onToggleRelayAgent: onToggleRelayAgent,
            ),
            Expanded(
              child: tabs.isEmpty
                  ? const SizedBox.shrink()
                  // IndexedStack keeps every tab mounted while painting only the
                  // active one. Removing inactive bodies would destroy view state:
                  // transcript scroll, terminal viewport and selection, focus, and
                  // composer drafts. Session data already persists in the VM; this
                  // preserves its presentation.
                  : IndexedStack(
                      index: activeIndex,
                      sizing: StackFit.expand,
                      children: [for (final id in tabs) _keyedBody(id)],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build a tab body with a stable session key across selection and reordering.
  ///
  /// Only the active tab receives focus so mounted terminals do not compete for
  /// keyboard input.
  Widget _keyedBody(String tabId) {
    final session = vm.session(tabId);
    if (session == null) return SizedBox.shrink(key: ValueKey('body-$tabId'));
    return _PaneBody(
      key: ValueKey('body-$tabId'),
      item: session,
      focused: focused && tabId == pane.active,
      active: tabId == pane.active,
      onFillEmpty: (terminal) => onFillEmpty(tabId, terminal),
    );
  }
}

/// Keep tab width consistent with active-tab auto-scroll calculations.
const double _kTabWidth = 188;

/// Resolve the icon shared by a tab and the all-tabs menu.
IconData _tabIcon(PaneItem? item) {
  if (item is TerminalSession) return Icons.terminal_outlined;
  if (item is FileViewerSession) return Icons.description_outlined;
  if (item is AgentSession &&
      item.projection.lifecycle == AgentProcessLifecycle.empty) {
    return Icons.edit_outlined;
  }
  return Icons.auto_awesome;
}

class _TabStrip extends StatefulWidget {
  const _TabStrip({
    required this.pane,
    required this.vm,
    required this.focused,
    required this.onCreateTab,
    required this.onSplit,
    required this.onHistoryAgent,
    required this.onRenameAgent,
    required this.onToggleRelayAgent,
  });

  final LeafPane pane;
  final CockpitViewModel vm;
  final bool focused;
  final VoidCallback onCreateTab;
  final ValueChanged<SplitDir> onSplit;
  final ValueChanged<String> onHistoryAgent;
  final void Function(String agentId, String name) onRenameAgent;
  final ValueChanged<String> onToggleRelayAgent;

  @override
  State<_TabStrip> createState() => _TabStripState();
}

class _TabStripState extends State<_TabStrip> {
  final ScrollController _scroll = ScrollController();
  bool _overflowing = false;
  bool _hovering = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollActiveIntoView();
      _syncOverflow();
    });
  }

  @override
  void didUpdateWidget(_TabStrip old) {
    super.didUpdateWidget(old);
    final activeChanged = old.pane.active != widget.pane.active;
    final countChanged = old.pane.tabs.length != widget.pane.tabs.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (activeChanged || countChanged) _scrollActiveIntoView();
      _syncOverflow();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _setHover(bool value) {
    if (value != _hovering) setState(() => _hovering = value);
  }

  /// Show the overflow control only when the tab strip actually overflows.
  void _syncOverflow() {
    if (!_scroll.hasClients) return;
    final over = _scroll.position.maxScrollExtent > 0.5;
    if (over != _overflowing) setState(() => _overflowing = over);
  }

  /// Scroll the fixed-width active tab into the visible strip area.
  void _scrollActiveIntoView() {
    if (!_scroll.hasClients) return;
    final index = widget.pane.tabs.indexOf(widget.pane.active);
    if (index < 0) return;
    final pos = _scroll.position;
    final start = index * _kTabWidth;
    final end = start + _kTabWidth;
    final viewStart = pos.pixels;
    final viewEnd = viewStart + pos.viewportDimension;
    double? target;
    if (start < viewStart) {
      target = start;
    } else if (end > viewEnd) {
      target = end - pos.viewportDimension;
    }
    if (target != null) {
      _scroll.animateTo(
        target.clamp(0.0, pos.maxScrollExtent),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _confirmClosePane(BuildContext context) async {
    final count = widget.pane.tabs.length;
    final ok = await showConfirmDialog(
      context,
      title: 'Close pane?',
      message:
          'This closes all $count tab(s) in this pane and ends the agents/'
          'terminals in it.',
      confirmLabel: 'Close',
      danger: true,
    );
    if (ok) widget.vm.closePane(widget.pane.id);
  }

  /// Show all tabs for direct selection when the strip overflows.
  Future<void> _showTabList(BuildContext anchor) async {
    final pane = widget.pane;
    final picked = await showAppMenu<String>(
      anchor,
      minWidth: 220,
      items: [
        for (final id in pane.tabs)
          AppMenuItem(
            value: id,
            label: widget.vm.session(id)?.title ?? '—',
            icon: _tabIcon(widget.vm.session(id)),
            selected: id == pane.active,
          ),
      ],
    );
    if (picked != null) widget.vm.selectTab(pane.id, picked);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final pane = widget.pane;
    // Recheck overflow after pane resize or tab addition and removal.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncOverflow();
    });
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: MouseRegion(
              onEnter: (_) => _setHover(true),
              onExit: (_) => _setHover(false),
              child: Scrollbar(
                controller: _scroll,
                // Reveal the scrollbar only while hovering an overflowing strip.
                thumbVisibility: _hovering && _overflowing,
                thickness: 3,
                radius: const Radius.circular(3),
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(scrollbars: false),
                  child: SingleChildScrollView(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < pane.tabs.length; i++)
                          _TabDropSlot(
                            index: i,
                            onInsert: (data, index) => widget.vm.moveTabToIndex(
                              data.paneId,
                              data.tabId,
                              pane.id,
                              index,
                            ),
                            child: _Tab(
                              item: widget.vm.session(pane.tabs[i]),
                              paneId: pane.id,
                              active: pane.tabs[i] == pane.active,
                              focused: widget.focused,
                              onSelect: () =>
                                  widget.vm.selectTab(pane.id, pane.tabs[i]),
                              onClose: () =>
                                  widget.vm.closeTab(pane.id, pane.tabs[i]),
                              onRename: (name) =>
                                  widget.onRenameAgent(pane.tabs[i], name),
                              onToggleRelay: () =>
                                  widget.onToggleRelayAgent(pane.tabs[i]),
                              onHistory: () =>
                                  widget.onHistoryAgent(pane.tabs[i]),
                            ),
                          ),
                        _TabAdd(onTap: widget.onCreateTab),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Offer direct tab selection only when the strip overflows.
          if (_overflowing)
            Builder(
              builder: (ctx) => _StripButton(
                icon: Icons.keyboard_arrow_down,
                tooltip: 'All tabs',
                onTap: () => _showTabList(ctx),
              ),
            ),
          _PaneTools(
            onSplitRight: () => widget.onSplit(SplitDir.vertical),
            onSplitDown: () => widget.onSplit(SplitDir.horizontal),
            onClosePane: () => _confirmClosePane(context),
          ),
        ],
      ),
    );
  }
}

/// Render a compact tab-strip action such as the overflow control.
class _StripButton extends StatelessWidget {
  const _StripButton({
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

class _Tab extends StatefulWidget {
  const _Tab({
    required this.item,
    required this.paneId,
    required this.active,
    required this.focused,
    required this.onSelect,
    required this.onClose,
    required this.onRename,
    required this.onToggleRelay,
    required this.onHistory,
  });

  final PaneItem? item;
  final String paneId;
  final bool active;
  final bool focused;
  final VoidCallback onSelect;
  final VoidCallback onClose;
  final ValueChanged<String> onRename;
  final VoidCallback onToggleRelay;
  final VoidCallback onHistory;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool _editing = false;
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();

  /// Last tap timestamp used for manual double-click detection.
  DateTime? _lastTapAt;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(_Tab old) {
    super.didUpdateWidget(old);
    // Cancel editing if this widget is rebound to another tab.
    if (old.item?.id != widget.item?.id && _editing) {
      setState(() => _editing = false);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Select immediately while detecting double-click rename or preview pinning.
  ///
  /// Manual detection avoids the delay that `DoubleTapGestureRecognizer` adds
  /// while holding the gesture arena for `kDoubleTapTimeout`.
  void _handleTap() {
    final s = widget.item;
    final agent = s is AgentSession ? s : null;
    final viewer = s is FileViewerSession ? s : null;
    final canRename =
        agent != null &&
        agent.projection.lifecycle != AgentProcessLifecycle.empty;
    final canPin = viewer != null && viewer.isPreview;
    final now = DateTime.now();
    final last = _lastTapAt;
    _lastTapAt = now;

    // A double-click renames an agent or pins a file preview.
    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 300)) {
      _lastTapAt = null; // Consume the second click.
      if (canPin) {
        viewer.pin();
        return;
      }
      if (canRename) {
        _startEditing();
        return;
      }
    }
    widget.onSelect();
  }

  void _startEditing() {
    final s = widget.item;
    if (s is! AgentSession) return;
    _ctrl.text = s.title;
    _ctrl.selection = TextSelection(
      baseOffset: 0,
      extentOffset: s.title.length,
    );
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _commitEdit() {
    if (!_editing) return;
    final name = _ctrl.text.trim().replaceAll(' ', '-');
    setState(() => _editing = false);
    if (name.isNotEmpty) widget.onRename(name);
  }

  void _cancelEdit() {
    setState(() => _editing = false);
  }

  void _onFocusChange() {
    if (!_focus.hasFocus && _editing) _commitEdit();
  }

  /// Close the tab, asking how to handle unsaved file edits when necessary.
  Future<void> _requestClose() async {
    final s = widget.item;
    if (s is! FileViewerSession || !s.dirty) {
      widget.onClose();
      return;
    }
    final choice = await showCloseDirtyDialog(context, fileName: s.title);
    if (!mounted) return;
    switch (choice) {
      case CloseDirtyChoice.cancel:
        return;
      case CloseDirtyChoice.dontSave:
        widget.onClose();
      case CloseDirtyChoice.save:
        // Close only after the current buffer saves; I/O failure keeps it open.
        final ok = await s.saveDraft?.call() ?? false;
        if (!mounted) return;
        if (ok) widget.onClose();
    }
  }

  Future<void> _showTabMenu(BuildContext menuCtx) async {
    final s = widget.item;
    if (s == null) return;
    final agent = s is AgentSession ? s : null;
    final isEmpty = agent?.projection.lifecycle == AgentProcessLifecycle.empty;
    final viewer = s is FileViewerSession ? s : null;
    final isPreview = viewer?.isPreview ?? false;

    final value = await showAppMenu<String>(
      menuCtx,
      minWidth: 150,
      items: [
        if (viewer != null && isPreview)
          const AppMenuItem(
            value: 'pin',
            label: 'Pin tab',
            icon: Icons.push_pin_outlined,
          ),
        if (agent != null && !isEmpty) ...[
          const AppMenuItem(
            value: 'rename',
            label: 'Rename',
            icon: Icons.edit_outlined,
          ),
          AppMenuItem(
            value: 'relay',
            label: 'Auto-relay',
            icon: Icons.cell_tower_outlined,
            selected: agent.autoStartRelay,
          ),
          const AppMenuItem(
            value: 'history',
            label: 'History',
            icon: Icons.history,
          ),
        ],
        const AppMenuItem(value: 'close', label: 'Close', icon: Icons.close),
      ],
    );
    if (!mounted) return;
    switch (value) {
      case 'pin':
        if (viewer != null) viewer.pin();
      case 'rename':
        _startEditing();
      case 'relay':
        widget.onToggleRelay();
      case 'history':
        widget.onHistory();
      case 'close':
        _requestClose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.item;
    if (s == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: s,
      builder: (_, _) {
        final colors = context.colors;
        final isFocusedActive = widget.active && widget.focused;
        final agent = s is AgentSession ? s : null;
        final projection = agent?.projection;
        final isEmpty = projection?.lifecycle == AgentProcessLifecycle.empty;
        final streaming = projection?.turn.working ?? false;
        final dirty = s is FileViewerSession && s.dirty;

        final icon = _tabIcon(s);

        // Use inline editing while renaming and italicize preview tabs like VS Code.
        final isPreview = s is FileViewerSession && s.isPreview;
        final titleWidget = _editing && agent != null
            ? CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape): _cancelEdit,
                },
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  onSubmitted: (_) => _commitEdit(),
                  style: context.typo.tab.copyWith(
                    fontSize: 12,
                    color: colors.text,
                  ),
                  borderRadius: BorderRadius.circular(7),
                  inputFormatters: [
                    FilteringTextInputFormatter(
                      RegExp(r' '),
                      allow: false,
                      replacementString: '-',
                    ),
                  ],
                ),
              )
            : Text(
                s.title,
                overflow: TextOverflow.ellipsis,
                style: context.typo.tab.copyWith(
                  color: isFocusedActive || widget.active
                      ? colors.text
                      : colors.text3,
                  fontStyle: isPreview ? FontStyle.italic : FontStyle.normal,
                ),
              );

        final tabBody = Container(
          height: 40,
          width: _kTabWidth,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.active ? colors.panel : colors.bg,
            border: Border(right: BorderSide(color: colors.border)),
          ),
          foregroundDecoration: isFocusedActive
              ? BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: colors.accent, width: 2),
                  ),
                )
              : null,
          padding: const EdgeInsets.only(left: 11, right: 7),
          child: Row(
            children: [
              if (s is FileViewerSession)
                FileTypeIcon.file(s.title, size: 15)
              else
                Icon(
                  icon,
                  size: 13,
                  color: isFocusedActive
                      ? colors.accentText
                      : (widget.active ? colors.text2 : colors.text3),
                ),
              const SizedBox(width: 7),
              Expanded(child: titleWidget),
              const SizedBox(width: 10),
              if (streaming) ...[
                SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    size: 10,
                    strokeWidth: 1.5,
                    color: colors.accent,
                  ),
                ),
                const SizedBox(width: 7),
              ] else if (s.unseenFinish) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: colors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
              ],
              _TabClose(onTap: _requestClose, dirty: dirty),
            ],
          ),
        );

        // While editing, disable dragging and tab selection so the field owns text
        // selection.
        if (_editing) return tabBody;

        // Builder supplies showAppMenu with a context backed by a RenderBox.
        final interactive = Builder(
          builder: (menuCtx) => GestureDetector(
            onTapUp: (d) => _handleTap(),
            onSecondaryTapUp: isEmpty ? null : (d) => _showTabMenu(menuCtx),
            child: tabBody,
          ),
        );

        return Draggable<TabDragData>(
          data: TabDragData(paneId: widget.paneId, tabId: s.id),
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: Transform.translate(
            offset: const Offset(12, 8),
            child: _DragFeedback(icon: icon, title: s.title),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: tabBody),
          child: interactive,
        );
      },
    );
  }
}

/// Reorder tabs by showing an insertion caret on the hovered tab edge.
class _TabDropSlot extends StatefulWidget {
  const _TabDropSlot({
    required this.index,
    required this.onInsert,
    required this.child,
  });

  final int index;
  final void Function(TabDragData data, int index) onInsert;
  final Widget child;

  @override
  State<_TabDropSlot> createState() => _TabDropSlotState();
}

class _TabDropSlotState extends State<_TabDropSlot> {
  /// `null` hides the caret; `true` inserts before and `false` after.
  bool? _before;

  void _update(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final local = box.globalToLocal(global);
    final before = local.dx < box.size.width / 2;
    if (before != _before) setState(() => _before = before);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DragTarget<TabDragData>(
      onMove: (d) => _update(d.offset),
      onLeave: (_) {
        if (_before != null) setState(() => _before = null);
      },
      onAcceptWithDetails: (d) {
        final before = _before ?? true;
        setState(() => _before = null);
        widget.onInsert(d.data, before ? widget.index : widget.index + 1);
      },
      builder: (context, candidate, rejected) {
        final caret = candidate.isNotEmpty ? _before : null;
        return Stack(
          children: [
            widget.child,
            if (caret != null)
              Positioned(
                top: 6,
                bottom: 6,
                left: caret ? 0 : null,
                right: caret ? null : 0,
                child: Container(
                  width: 2.5,
                  decoration: BoxDecoration(
                    color: colors.accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TabClose extends StatefulWidget {
  const _TabClose({required this.onTap, this.dirty = false});
  final VoidCallback onTap;

  /// Replace the close icon with a dot for unsaved edits until hovered.
  final bool dirty;

  @override
  State<_TabClose> createState() => _TabCloseState();
}

class _TabCloseState extends State<_TabClose> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Show a dot for unhovered unsaved tabs and the close icon otherwise.
    final showDot = widget.dirty && !_hover;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: HoverTap(
        borderRadius: BorderRadius.circular(4),
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: showDot
              ? Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: colors.accent,
                    shape: BoxShape.circle,
                  ),
                )
              : Icon(Icons.close, size: 12, color: colors.text3),
        ),
      ),
    );
  }
}

/// Open an empty New tab that lets the user choose agent or terminal content.
class _TabAdd extends StatelessWidget {
  const _TabAdd({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      tooltip: (context) => const TooltipContainer(child: Text('New tab')),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: colors.border)),
            ),
            child: Icon(Icons.add, size: 14, color: colors.text4),
          ),
        ),
      ),
    );
  }
}

class _PaneTools extends StatelessWidget {
  const _PaneTools({
    required this.onSplitRight,
    required this.onSplitDown,
    required this.onClosePane,
  });

  final VoidCallback onSplitRight;
  final VoidCallback onSplitDown;
  final VoidCallback onClosePane;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final iconColor = colors.text3;
    const spacing = 13.0;
    Widget btn(Widget icon, String tip, VoidCallback onTap) => Tooltip(
      tooltip: (context) => TooltipContainer(child: Text(tip)),
      child: HoverTap(
        borderRadius: BorderRadius.circular(5),
        onTap: onTap,
        child: SizedBox(width: spacing, height: spacing, child: icon),
      ),
    );
    // Use one split-screen shape in two orientations: stacked means split down,
    // while side-by-side means split right.

    return Padding(
      padding: const EdgeInsets.only(right: spacing),
      child: Row(
        spacing: 12,
        children: [
          btn(
            _SplitterScreenIcon(
              type: _SplitterScreenIconType.horizontal,
              color: iconColor,
            ),
            'Split right',
            onSplitRight,
          ),
          btn(
            _SplitterScreenIcon(
              type: _SplitterScreenIconType.vertical,
              color: iconColor,
            ),
            'Split down',
            onSplitDown,
          ),
          btn(
            _SplitterScreenIcon(
              type: _SplitterScreenIconType.close,
              color: iconColor,
            ),
            'Close pane',
            onClosePane,
          ),
        ],
      ),
    );
  }
}

class _PaneBody extends StatefulWidget {
  const _PaneBody({
    super.key,
    required this.item,
    required this.focused,
    required this.active,
    required this.onFillEmpty,
  });
  final PaneItem item;
  final bool focused;

  /// Whether this is the pane's visible tab, independently of pane focus.
  ///
  /// Media viewers use this to pause while inactive because [IndexedStack] keeps
  /// every tab mounted.
  final bool active;

  /// Fills the empty tab with a terminal when `true`, otherwise an agent.
  final ValueChanged<bool> onFillEmpty;

  @override
  State<_PaneBody> createState() => _PaneBodyState();
}

class _PaneBodyState extends State<_PaneBody> {
  final ScrollController _scroll = ScrollController();
  final FocusNode _terminalFocus = FocusNode();

  static const double _stickThreshold = 80;

  /// Track the environment gate for an empty agent tab and its setup fallback.
  bool _checkingAgent = false;
  bool _showAgentSetup = false;

  /// Check agent readiness before filling an empty tab.
  ///
  /// A ready environment starts the agent; otherwise the tab reveals
  /// [AgentSetupChecklist]. Terminal creation bypasses this gate.
  Future<void> _onNewAgent() async {
    final setup = context.read<SetupViewModel>();
    setState(() => _checkingAgent = true);
    await setup.recheckAll();
    if (!mounted) return;
    setState(() => _checkingAgent = false);
    if (setup.agentReady) {
      widget.onFillEmpty(false);
    } else {
      setState(() => _showAgentSetup = true);
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.item is TerminalSession && widget.focused) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _terminalFocus.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(_PaneBody old) {
    super.didUpdateWidget(old);
    if (widget.item is! TerminalSession) return;
    if (widget.focused && !old.focused) {
      // Defer focus until after the frame so requestFocus during onTapDown does
      // not interfere with tab selection's onTapUp in the same gesture cycle.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _terminalFocus.requestFocus();
      });
    } else if (!widget.focused && old.focused) {
      _terminalFocus.unfocus();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _terminalFocus.dispose();
    super.dispose();
  }

  /// Intercept the terminal paste shortcut to support clipboard images.
  ///
  /// `TerminalView` pastes only text, so Cmd+V on macOS and Ctrl+V elsewhere
  /// delegate to [TerminalSession.pasteFromClipboard], which sends `\x16` for
  /// an image. macOS also prefers Cmd+V because its IME can consume raw Ctrl+V
  /// as `pageDown`. Other keys continue through normal terminal handling.
  KeyEventResult _onTerminalKey(KeyEvent event, TerminalSession session) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyV) {
      return KeyEventResult.ignored;
    }
    // Prefer Cmd+V on macOS and Ctrl+V elsewhere, while accepting Ctrl+V on
    // macOS if the IME lets it through.
    final keys = HardwareKeyboard.instance;
    final isPaste =
        (Platform.isMacOS && keys.isMetaPressed) || keys.isControlPressed;
    if (!isPaste) return KeyEventResult.ignored;
    session.pasteFromClipboard();
    return KeyEventResult.handled;
  }

  void _maybeStickToBottom() {
    final bool stick;
    if (!_scroll.hasClients) {
      stick = true;
    } else {
      final pos = _scroll.position;
      stick = pos.pixels >= pos.maxScrollExtent - _stickThreshold;
    }
    if (!stick) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    // File viewer: Markdown, text, image, and editable file surfaces.
    if (item is FileViewerSession) {
      return FileViewer(
        session: item,
        active: widget.active,
        focused: widget.focused,
        onSave: (content) =>
            context.read<CockpitViewModel>().saveFile(item.id, content),
      );
    }

    // TerminalView updates itself from the Terminal model.
    if (item is TerminalSession) {
      final settings = context.watch<SettingsController>().settings;
      final termFont = settings.terminalFont;
      // The terminal has its own optional font and uses the configured code size.
      // Global interface zoom is applied by `_AppZoom`, so do not scale it here.
      final termStyle = (termFont == null || termFont.isEmpty)
          ? TerminalStyle(fontSize: settings.codeSize)
          : TerminalStyle(fontSize: settings.codeSize, fontFamily: termFont);
      return ColoredBox(
        color: context.colors.panel,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 0, 8),
          child: TerminalPane(
            terminal: item.terminal,
            focusNode: _terminalFocus,
            // xterm's IME/TextInput path fails on Windows desktop with "Could not
            // set client, view ID is null" and prevents typing. Hardware-only
            // mode reads raw KeyEvents there; macOS retains IME composition.
            hardwareKeyboardOnly: Platform.isWindows,
            // Intercept paste to support clipboard images; xterm's default paste
            // handles text only. See `_onTerminalKey`.
            onKeyEvent: (event) => _onTerminalKey(event, item),
            theme: cockpitTerminalThemeFor(Theme.of(context).brightness),
            textStyle: termStyle,
          ),
        ),
      );
    }

    final agent = item as AgentSession;
    return ListenableBuilder(
      listenable: agent,
      builder: (context, _) {
        if (agent.projection.lifecycle == AgentProcessLifecycle.empty) {
          if (_showAgentSetup) {
            return AgentSetupChecklist(
              onReady: () => widget.onFillEmpty(false),
              onCancel: () => setState(() => _showAgentSetup = false),
            );
          }
          return Stack(
            children: [
              EmptyPane(
                onNewAgent: _onNewAgent,
                onNewTerminal: () => widget.onFillEmpty(true),
              ),
              if (_checkingAgent)
                Positioned.fill(
                  child: ColoredBox(
                    color: context.colors.panel.withValues(alpha: 0.6),
                    child: const Center(
                      child: CircularProgressIndicator(size: 18),
                    ),
                  ),
                ),
            ],
          );
        }
        _maybeStickToBottom();
        return Stack(
          children: [
            Positioned.fill(
              child: AgentTranscript(
                entries: agent.entries,
                controller: _scroll,
                onUiResponse: agent.respondUi,
                bottomPadding: 150,
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              // Center and cap composer width in wide panes while filling narrow
              // panes.
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: AgentComposer(
                    key: ValueKey('composer-${agent.id}'),
                    session: agent,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ============================================================================
// Drag and drop tabs between panes
// ============================================================================

/// Identify the tab and source pane carried during a drag.
class TabDragData {
  const TabDragData({required this.paneId, required this.tabId});
  final String paneId;
  final String tabId;
}

/// Describe where a tab will be dropped within a pane.
///
/// [strip] and [center] dock it as a tab; edge zones create a split.
enum _DropZone { strip, center, left, right, top, bottom }

/// Follow the cursor with a compact tab preview during dragging.
class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      constraints: const BoxConstraints(maxWidth: 200),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
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
          Icon(icon, size: 13, color: colors.accentText),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: context.typo.tab.copyWith(color: colors.text),
            ),
          ),
        ],
      ),
    );
  }
}

/// Accept tab and file drops over a [PaneView].
///
/// Tab drags preview dock or split zones before committing the workspace move;
/// file drags open a tab or insert a path into the active terminal.
class PaneDropZone extends StatefulWidget {
  const PaneDropZone({
    super.key,
    required this.paneId,
    required this.vm,
    required this.child,
  });

  final String paneId;
  final CockpitViewModel vm;
  final Widget child;

  @override
  State<PaneDropZone> createState() => _PaneDropZoneState();
}

class _PaneDropZoneState extends State<PaneDropZone> {
  static const double _stripHeight = 40;
  static const double _edge =
      0.25; // Fraction of each edge that creates a split.

  _DropZone? _zone;
  bool _fileOver = false;

  /// Return the pane's active session, or `null` when it cannot be resolved.
  PaneItem? _activeSession() {
    final projectId = widget.vm.selectedProjectId;
    if (projectId == null) return null;
    final tree = widget.vm.tree(projectId);
    if (tree == null) return null;
    final leaf = findLeaf(tree, widget.paneId);
    final activeId = leaf?.active;
    if (activeId == null) return null;
    return widget.vm.session(activeId);
  }

  _DropZone _zoneAt(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return _DropZone.center;
    final local = box.globalToLocal(global);
    final size = box.size;
    if (local.dy <= _stripHeight) return _DropZone.strip;

    final bw = size.width;
    final bh = size.height - _stripHeight;
    if (bw <= 0 || bh <= 0) return _DropZone.center;
    final fx = (local.dx / bw).clamp(0.0, 1.0);
    final fy = ((local.dy - _stripHeight) / bh).clamp(0.0, 1.0);

    // Choose the shallowest edge depth within the split threshold.
    var best = _DropZone.center;
    var bestDepth = _edge;
    void consider(_DropZone zone, double depth) {
      if (depth < bestDepth) {
        bestDepth = depth;
        best = zone;
      }
    }

    consider(_DropZone.left, fx);
    consider(_DropZone.right, 1 - fx);
    consider(_DropZone.top, fy);
    consider(_DropZone.bottom, 1 - fy);
    return best;
  }

  void _commit(TabDragData data) {
    final zone = _zone ?? _DropZone.center;
    final vm = widget.vm;
    final target = widget.paneId;
    switch (zone) {
      case _DropZone.strip:
      case _DropZone.center:
        vm.moveTabToPane(data.paneId, data.tabId, target);
      case _DropZone.left:
        vm.moveTabToNewSplit(
          data.paneId,
          data.tabId,
          target,
          SplitDir.vertical,
          before: true,
        );
      case _DropZone.right:
        vm.moveTabToNewSplit(
          data.paneId,
          data.tabId,
          target,
          SplitDir.vertical,
          before: false,
        );
      case _DropZone.top:
        vm.moveTabToNewSplit(
          data.paneId,
          data.tabId,
          target,
          SplitDir.horizontal,
          before: true,
        );
      case _DropZone.bottom:
        vm.moveTabToNewSplit(
          data.paneId,
          data.tabId,
          target,
          SplitDir.horizontal,
          before: false,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    // The outer target opens a tree file as a tab. The composer's nested string
    // target wins when hit and turns that same drag into an @mention.
    return DragTarget<String>(
      hitTestBehavior: HitTestBehavior.opaque,
      onMove: (_) {
        if (!_fileOver) setState(() => _fileOver = true);
      },
      onLeave: (_) {
        if (_fileOver) setState(() => _fileOver = false);
      },
      onAcceptWithDetails: (d) {
        final session = _activeSession();
        if (session is TerminalSession) {
          // An active terminal inserts the absolute path as typed PTY input.
          session.insertText(d.data);
        } else {
          widget.vm.openFile(d.data, inPane: widget.paneId);
        }
        setState(() => _fileOver = false);
      },
      builder: (context, fileCandidate, fileRejected) {
        final fileOver = _fileOver && fileCandidate.isNotEmpty;
        // The inner target moves tabs between panes.
        return DragTarget<TabDragData>(
          hitTestBehavior: HitTestBehavior.opaque,
          onMove: (d) {
            final z = _zoneAt(d.offset);
            if (z != _zone) setState(() => _zone = z);
          },
          onLeave: (_) {
            if (_zone != null) setState(() => _zone = null);
          },
          onAcceptWithDetails: (d) {
            _commit(d.data);
            setState(() => _zone = null);
          },
          builder: (context, candidate, rejected) {
            final dragging = candidate.isNotEmpty && _zone != null;
            return Stack(
              children: [
                widget.child,
                if (dragging)
                  Positioned.fill(
                    child: IgnorePointer(child: _ZonePreview(zone: _zone!)),
                  ),
                // Subtly indicate that dropping the file will open it as a tab.
                if (fileOver)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: context.colors.accentSoft,
                          border: Border.all(
                            color: context.colors.accent,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Preview the drop zone as a split half, full dock area, or tab-strip band.
class _ZonePreview extends StatelessWidget {
  const _ZonePreview({required this.zone});
  final _DropZone zone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (zone == _DropZone.strip) {
      return Align(
        alignment: Alignment.topCenter,
        child: Container(
          height: 40,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.accentSoft,
            border: Border(bottom: BorderSide(color: colors.accent, width: 2)),
          ),
          child: Text(
            'Drop here to move the tab',
            style: context.typo.tab.copyWith(color: colors.accentText),
          ),
        ),
      );
    }

    final (align, wf, hf, label) = switch (zone) {
      _DropZone.center => (Alignment.center, 1.0, 1.0, 'Dock as tab'),
      _DropZone.left => (Alignment.centerLeft, 0.5, 1.0, null),
      _DropZone.right => (Alignment.centerRight, 0.5, 1.0, null),
      _DropZone.top => (Alignment.topCenter, 1.0, 0.5, null),
      _DropZone.bottom => (Alignment.bottomCenter, 1.0, 0.5, null),
      _DropZone.strip => (Alignment.center, 1.0, 1.0, null), // Unreachable.
    };

    return Padding(
      // Keep split highlighting within the body, below the tab strip.
      padding: const EdgeInsets.only(top: 40),
      child: Align(
        alignment: align,
        child: FractionallySizedBox(
          widthFactor: wf,
          heightFactor: hf,
          child: Container(
            margin: const EdgeInsets.all(8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.accentSoft,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.accent, width: 2),
            ),
            child: label == null
                ? null
                : Text(
                    label,
                    style: context.typo.tab.copyWith(color: colors.accentText),
                  ),
          ),
        ),
      ),
    );
  }
}

enum _SplitterScreenIconType { horizontal, vertical, close }

class _SplitterScreenIcon extends StatelessWidget {
  final _SplitterScreenIconType type;
  final Color color;
  const _SplitterScreenIcon({required this.type, required this.color});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final size = min(width, height);
        final borderLine = size * 0.10;
        final borderRadius = size * 0.10;
        final gap = size * 0.1;

        if (_SplitterScreenIconType.close == type) {
          return SizedBox(
            width: size,
            height: size,
            child: Transform.rotate(
              angle: 45 * pi / 180,
              child: Stack(
                children: [
                  Center(
                    child: Container(
                      width: borderRadius,
                      height: height,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(borderRadius),
                        color: color,
                      ),
                    ),
                  ),
                  Center(
                    child: Container(
                      width: width,
                      height: borderRadius,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(borderRadius),
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final children = [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: color, width: borderLine),
                borderRadius: BorderRadius.circular(borderRadius),
              ),
            ),
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: color, width: borderLine),
                borderRadius: BorderRadius.circular(borderRadius),
              ),
            ),
          ),
        ];

        return Center(
          child: SizedBox(
            width: height,
            height: height,
            child: type == _SplitterScreenIconType.vertical
                ? Column(spacing: gap, children: children)
                : Row(spacing: gap, children: children),
          ),
        );
      },
    );
  }
}
