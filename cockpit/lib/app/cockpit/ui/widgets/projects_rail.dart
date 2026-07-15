import 'dart:io' show Platform;

import 'package:cockpit/app/cockpit/domain/entities/git_info.dart';
import 'package:cockpit/app/cockpit/domain/entities/project.dart';
import 'package:cockpit/app/core/ui/widgets/app_menu.dart';
import 'package:cockpit/app/cockpit/ui/widgets/update_card.dart';
import 'package:cockpit/app/cockpit/ui/widgets/workspace_avatar.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Navigate root workspaces and their worktrees from the left rail.
///
/// The rail combines workspace identity, Git and notification state, reorder
/// controls, update status, and machine-level settings navigation.
class ProjectsRail extends StatefulWidget {
  const ProjectsRail({
    super.key,
    required this.projects,
    required this.worktreesOf,
    required this.selectedId,
    required this.notificationCount,
    required this.gitInfo,
    required this.onSelect,
    required this.onAdd,
    required this.onConfigure,
    required this.onDelete,
    required this.onCreateWorktree,
    required this.onRemoveWorktree,
    required this.onOpenSettings,
    required this.onReorder,
    this.width = 252,
  });

  /// Current page-controlled rail width; it is not persisted here.
  final double width;

  /// Root workspaces only; [worktreesOf] supplies their worktrees.
  final List<Project> projects;

  /// Resolves a root workspace's worktrees in Git order.
  final List<Project> Function(String rootId) worktreesOf;

  final String? selectedId;
  final int Function(String projectId) notificationCount;
  final GitInfo? Function(String projectId) gitInfo;
  final ValueChanged<String> onSelect;
  final Future<bool> Function() onAdd;
  final ValueChanged<Project> onConfigure;
  final ValueChanged<Project> onDelete;

  /// Starts worktree creation for a Git-backed root workspace.
  final ValueChanged<Project> onCreateWorktree;

  /// Starts worktree removal; the page owns confirmation.
  final ValueChanged<Project> onRemoveWorktree;

  /// Opens Settings from the footer action.
  final VoidCallback onOpenSettings;

  /// Moves [movedId] before or after [targetId] in root workspace order.
  final void Function(String movedId, String targetId, bool before) onReorder;

  @override
  State<ProjectsRail> createState() => _ProjectsRailState();
}

class _ProjectsRailState extends State<ProjectsRail> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Build worktree rows with a terminating branch line on the final item.
  List<Widget> _forkItems(Project project) {
    final forks = widget.worktreesOf(project.id);
    return [
      for (var i = 0; i < forks.length; i++)
        _WorktreeItem(
          worktree: forks[i],
          isLast: i == forks.length - 1,
          selected: forks[i].id == widget.selectedId,
          notifications: widget.notificationCount(forks[i].id),
          git: widget.gitInfo(forks[i].id),
          onTap: () => widget.onSelect(forks[i].id),
          onRemove: () => widget.onRemoveWorktree(forks[i]),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final projects = widget.projects;
    final onAdd = widget.onAdd;
    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border(right: BorderSide(color: colors.border)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
            child: Row(
              children: [
                Icon(Icons.layers_outlined, size: 16, color: colors.text2),
                const SizedBox(width: 9),
                Text(
                  'Workspaces',
                  style: context.typo.title.copyWith(color: colors.text),
                ),
                const Spacer(),
                // With no workspace, creation stays centered in the empty view.
                if (projects.isNotEmpty)
                  _SmallIcon(
                    icon: Icons.add,
                    tooltip: 'New workspace',
                    onTap: () => onAdd(),
                  ),
              ],
            ),
          ),
          Expanded(
            child: projects.isEmpty
                ? const _EmptyRail()
                : Scrollbar(
                    controller: _scroll,
                    thumbVisibility: true,
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(
                        context,
                      ).copyWith(scrollbars: false),
                      child: ListView(
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        children: [
                          for (final project in projects) ...[
                            _WorkspaceReorderable(
                              projectId: project.id,
                              title: project.name,
                              colorValue: project.colorValue,
                              initial: project.initial,
                              imagePath: project.imagePath,
                              onReorder: widget.onReorder,
                              child: _ProjectItem(
                                project: project,
                                selected: project.id == widget.selectedId,
                                notifications: widget.notificationCount(
                                  project.id,
                                ),
                                git: widget.gitInfo(project.id),
                                // Worktree creation applies only to Git repositories.
                                canCreateWorktree:
                                    widget.gitInfo(project.id) != null,
                                onTap: () => widget.onSelect(project.id),
                                onConfigure: () => widget.onConfigure(project),
                                onDelete: () => widget.onDelete(project),
                                onCreateWorktree: () =>
                                    widget.onCreateWorktree(project),
                              ),
                            ),
                            // Worktrees remain expanded beneath their root workspace.
                            ..._forkItems(project),
                          ],
                        ],
                      ),
                    ),
                  ),
          ),
          // Keep the in-app update notice above the machine name.
          const UpdateCard(),
          Container(
            // Match the file viewer footer height to align the base.
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.border)),
            ),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: colors.online,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: colors.online, blurRadius: 8)],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    Platform.localHostname,
                    overflow: TextOverflow.ellipsis,
                    style: context.typo.label.copyWith(color: colors.text2),
                  ),
                ),
                _SmallIcon(
                  icon: Icons.settings_outlined,
                  tooltip: 'Settings',
                  onTap: widget.onOpenSettings,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectItem extends StatelessWidget {
  const _ProjectItem({
    required this.project,
    required this.selected,
    required this.notifications,
    required this.git,
    required this.canCreateWorktree,
    required this.onTap,
    required this.onConfigure,
    required this.onDelete,
    required this.onCreateWorktree,
  });

  final Project project;
  final bool selected;
  final int notifications;
  final GitInfo? git;
  final bool canCreateWorktree;
  final VoidCallback onTap;
  final VoidCallback onConfigure;
  final VoidCallback onDelete;
  final VoidCallback onCreateWorktree;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final gitInfo = git;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: HoverTap(
        color: selected ? colors.panel2 : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(9, 7, 5, 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            WorkspaceAvatar(
              imagePath: project.imagePath,
              colorValue: project.colorValue,
              initial: project.initial,
              size: 30,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    project.name,
                    overflow: TextOverflow.ellipsis,
                    style: context.typo.body.copyWith(
                      fontSize: 13.5,
                      color: colors.text,
                      fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                    ),
                  ),
                  // Show the Git row only for repositories.
                  if (gitInfo != null) ...[
                    const SizedBox(height: 4),
                    _GitBadge(info: gitInfo),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (notifications > 0) ...[
              Container(
                constraints: const BoxConstraints(minWidth: 18),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: colors.accent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$notifications',
                  textAlign: TextAlign.center,
                  style: context.typo.mono.copyWith(
                    fontSize: 11,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
            _MenuButton(
              canCreateWorktree: canCreateWorktree,
              onConfigure: onConfigure,
              onDelete: onDelete,
              onCreateWorktree: onCreateWorktree,
            ),
          ],
        ),
      ),
    );
  }
}

/// Render a worktree beneath its root workspace using branch identity.
///
/// The tree line remains outside row highlighting, while dirty state,
/// notifications, and removal controls appear on the right.
class _WorktreeItem extends StatelessWidget {
  const _WorktreeItem({
    required this.worktree,
    required this.isLast,
    required this.selected,
    required this.notifications,
    required this.git,
    required this.onTap,
    required this.onRemove,
  });

  final Project worktree;

  /// Whether the branch line terminates here instead of continuing downward.
  final bool isLast;
  final bool selected;
  final int notifications;
  final GitInfo? git;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Fill the row outside its highlight so adjacent branch lines connect.
          SizedBox(
            width: 30,
            child: CustomPaint(
              painter: _ForkLinePainter(color: colors.border, isLast: isLast),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: HoverTap(
                color: selected ? colors.panel2 : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
                onTap: onTap,
                padding: const EdgeInsets.fromLTRB(0, 5, 7, 5),
                child: Row(
                  children: [
                    Icon(Icons.call_split, size: 12, color: colors.text3),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        worktree.name,
                        overflow: TextOverflow.ellipsis,
                        style: context.typo.mono.copyWith(
                          fontSize: 12,
                          color: selected ? colors.text : colors.text2,
                          fontWeight: selected
                              ? FontWeight.w500
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _WorktreeSignal(
                      dirtyCount: git?.dirtyCount ?? 0,
                      hasNotification: notifications > 0,
                    ),
                    const SizedBox(width: 2),
                    _ForkMenuButton(branch: worktree.name, onRemove: onRemove),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Show compact branch copy and worktree removal actions.
class _ForkMenuButton extends StatelessWidget {
  const _ForkMenuButton({required this.branch, required this.onRemove});

  final String branch;
  final VoidCallback onRemove;

  Future<void> _show(BuildContext context) async {
    final pick = await showAppMenu<String>(
      context,
      items: const [
        AppMenuItem(
          value: 'copy',
          label: 'Copy branch',
          icon: Icons.content_copy,
        ),
        AppMenuItem(
          value: 'remove',
          label: 'Remove',
          icon: Icons.delete_outline,
          danger: true,
        ),
      ],
    );
    if (pick == 'copy') {
      await Clipboard.setData(ClipboardData(text: branch));
    }
    if (pick == 'remove') onRemove();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      tooltip: (context) => const TooltipContainer(child: Text('Options')),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (_) => _show(context),
          child: SizedBox(
            width: 22,
            height: 22,
            child: Icon(Icons.more_vert, size: 14, color: context.colors.text3),
          ),
        ),
      ),
    );
  }
}

/// Combine worktree dirty count and completion notification in one signal.
///
/// Dirty worktrees show a count badge; clean ones show a dot. A completion
/// notification accents the clean dot or overlays the dirty badge.
class _WorktreeSignal extends StatelessWidget {
  const _WorktreeSignal({
    required this.dirtyCount,
    required this.hasNotification,
  });

  final int dirtyCount;
  final bool hasNotification;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    if (dirtyCount > 0) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 16),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: colors.editedBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$dirtyCount',
              textAlign: TextAlign.center,
              style: typo.mono.copyWith(
                fontSize: 10.5,
                color: colors.edited,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (hasNotification)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: colors.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.bg, width: 1.2),
                ),
              ),
            ),
        ],
      );
    }
    // A clean worktree uses an accent dot for notifications and gray otherwise.
    return Container(
      width: 7,
      height: 7,
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        color: hasNotification ? colors.accent : colors.text3,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Paint the tree line connecting a worktree to its root workspace.
///
/// Middle branches continue to the next row; the final branch stops at the
/// horizontal tick.
class _ForkLinePainter extends CustomPainter {
  _ForkLinePainter({required this.color, required this.isLast});
  final Color color;
  final bool isLast;

  /// Horizontal position aligned beneath the root workspace.
  static const double _x = 20;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    final midY = size.height / 2;
    canvas.drawLine(
      Offset(_x, 0),
      Offset(_x, isLast ? midY : size.height),
      paint,
    );
    canvas.drawLine(Offset(_x, midY), Offset(size.width, midY), paint);
  }

  @override
  bool shouldRepaint(covariant _ForkLinePainter old) =>
      old.color != color || old.isLast != isLast;
}

/// Summarize branch, divergence, and dirty-file state in a compact Git badge.
class _GitBadge extends StatelessWidget {
  const _GitBadge({required this.info});
  final GitInfo info;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    final dirty = info.isDirty;
    final fg = dirty ? colors.warn : colors.text3;
    final bg = dirty ? colors.editedBg : colors.panel3;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 1, 5, 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.call_split, size: 9, color: fg),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              info.branch,
              overflow: TextOverflow.ellipsis,
              style: typo.mono.copyWith(
                fontSize: 9.5,
                color: fg,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (info.behind > 0) ...[
            const SizedBox(width: 4),
            _AheadBehind(glyph: '↓', count: info.behind, color: colors.warn),
          ],
          if (info.ahead > 0) ...[
            const SizedBox(width: 3),
            _AheadBehind(
              glyph: '↑',
              count: info.ahead,
              color: colors.accentText,
            ),
          ],
          if (dirty) ...[
            const SizedBox(width: 4),
            Text(
              '${info.dirtyCount}',
              style: typo.mono.copyWith(
                fontSize: 9.5,
                color: colors.edited,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Show a compact count of commits ahead of or behind the upstream branch.
class _AheadBehind extends StatelessWidget {
  const _AheadBehind({
    required this.glyph,
    required this.count,
    required this.color,
  });
  final String glyph;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$glyph$count',
      style: context.typo.mono.copyWith(
        fontSize: 9.5,
        color: color,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// Show compact workspace actions for worktrees, settings, and closing.
class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.canCreateWorktree,
    required this.onConfigure,
    required this.onDelete,
    required this.onCreateWorktree,
  });

  final bool canCreateWorktree;
  final VoidCallback onConfigure;
  final VoidCallback onDelete;
  final VoidCallback onCreateWorktree;

  Future<void> _show(BuildContext context) async {
    final pick = await showAppMenu<String>(
      context,
      items: [
        // Offer worktree creation only for a Git repository.
        if (canCreateWorktree)
          const AppMenuItem(
            value: 'worktree',
            label: 'Create worktree',
            icon: Icons.call_split,
          ),
        const AppMenuItem(
          value: 'config',
          label: 'Settings',
          icon: Icons.settings_outlined,
        ),
        const AppMenuItem(
          value: 'delete',
          label: 'Close',
          icon: Icons.close,
          danger: true,
        ),
      ],
    );
    if (pick == 'worktree') onCreateWorktree();
    if (pick == 'config') onConfigure();
    if (pick == 'delete') onDelete();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      tooltip: (context) => const TooltipContainer(child: Text('Options')),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (_) => _show(context),
          child: SizedBox(
            width: 26,
            height: 26,
            child: Icon(Icons.more_vert, size: 16, color: context.colors.text3),
          ),
        ),
      ),
    );
  }
}

class _EmptyRail extends StatelessWidget {
  const _EmptyRail();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'No workspaces yet.',
          textAlign: TextAlign.center,
          style: context.typo.label.copyWith(color: colors.text3),
        ),
      ),
    );
  }
}

class _SmallIcon extends StatelessWidget {
  const _SmallIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      tooltip: (context) => TooltipContainer(child: Text(tooltip)),
      child: HoverTap(
        borderRadius: BorderRadius.circular(5),
        onTap: onTap,
        child: SizedBox(
          width: 26,
          height: 26,
          child: Icon(icon, size: 16, color: colors.text3),
        ),
      ),
    );
  }
}

/// Reorder root workspaces by dragging them above or below one another.
///
/// A horizontal caret previews the insertion side before [onReorder] runs.
/// Worktrees are excluded because their ordering follows their root.
class _WorkspaceReorderable extends StatefulWidget {
  const _WorkspaceReorderable({
    required this.projectId,
    required this.title,
    required this.colorValue,
    required this.initial,
    required this.imagePath,
    required this.onReorder,
    required this.child,
  });

  final String projectId;
  final String title;
  final int colorValue;
  final String initial;
  final String? imagePath;
  final void Function(String movedId, String targetId, bool before) onReorder;
  final Widget child;

  @override
  State<_WorkspaceReorderable> createState() => _WorkspaceReorderableState();
}

class _WorkspaceReorderableState extends State<_WorkspaceReorderable> {
  /// `null` hides the caret; `true` inserts above and `false` below.
  bool? _before;

  void _update(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final local = box.globalToLocal(global);
    final before = local.dy < box.size.height / 2;
    if (before != _before) setState(() => _before = before);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != widget.projectId,
      onMove: (d) => _update(d.offset),
      onLeave: (_) {
        if (_before != null) setState(() => _before = null);
      },
      onAcceptWithDetails: (d) {
        final before = _before ?? true;
        setState(() => _before = null);
        widget.onReorder(d.data, widget.projectId, before);
      },
      builder: (context, candidate, rejected) {
        final caret = candidate.isNotEmpty ? _before : null;
        return Stack(
          children: [
            // Start dragging immediately. Desktop rail scrolling uses wheel or
            // trackpad PointerScroll rather than a drag gesture, so this does not
            // conflict with scrolling, selection, or the menu button.
            Draggable<String>(
              data: widget.projectId,
              dragAnchorStrategy: pointerDragAnchorStrategy,
              feedback: Transform.translate(
                offset: const Offset(10, 8),
                child: _WorkspaceDragChip(
                  title: widget.title,
                  colorValue: widget.colorValue,
                  initial: widget.initial,
                  imagePath: widget.imagePath,
                ),
              ),
              childWhenDragging: Opacity(opacity: 0.3, child: widget.child),
              child: widget.child,
            ),
            if (caret != null)
              Positioned(
                left: 8,
                right: 8,
                top: caret ? 0 : null,
                bottom: caret ? null : 2,
                child: Container(
                  height: 2.5,
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

/// Follow the cursor with workspace identity while reordering.
class _WorkspaceDragChip extends StatelessWidget {
  const _WorkspaceDragChip({
    required this.title,
    required this.colorValue,
    required this.initial,
    required this.imagePath,
  });

  final String title;
  final int colorValue;
  final String initial;
  final String? imagePath;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
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
          WorkspaceAvatar(
            imagePath: imagePath,
            colorValue: colorValue,
            initial: initial,
            size: 22,
            radius: 6,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: context.typo.label.copyWith(color: colors.text),
            ),
          ),
        ],
      ),
    );
  }
}
