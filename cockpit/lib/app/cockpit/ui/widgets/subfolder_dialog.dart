import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Choose the project subfolder in which an agent or terminal will work.
///
/// Navigation remains rooted within the project. Returns the selected relative
/// path (`''` for the root), or `null` when canceled. [loadSubfolders] is called
/// on demand with a relative path and must return its immediate subfolders.
Future<String?> showSubfolderDialog(
  BuildContext context, {
  required String projectName,
  required Future<List<String>> Function(String relativePath) loadSubfolders,
}) {
  return showDialog<String>(
    context: context,
    barrierColor: const Color(0x99000000),
    builder: (context) => _SubfolderDialog(
      projectName: projectName,
      loadSubfolders: loadSubfolders,
    ),
  );
}

class _SubfolderDialog extends StatefulWidget {
  const _SubfolderDialog({
    required this.projectName,
    required this.loadSubfolders,
  });

  final String projectName;
  final Future<List<String>> Function(String relativePath) loadSubfolders;

  @override
  State<_SubfolderDialog> createState() => _SubfolderDialogState();
}

class _SubfolderDialogState extends State<_SubfolderDialog> {
  /// Current relative path, empty at the root and `/`-separated otherwise.
  String _rel = '';
  List<String> _children = const <String>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load(_rel);
  }

  /// Segments of the current path, empty at the root.
  List<String> get _segments =>
      _rel.isEmpty ? const <String>[] : _rel.split('/');

  Future<void> _load(String rel) async {
    setState(() {
      _loading = true;
      _rel = rel;
    });
    final children = await widget.loadSubfolders(rel);
    if (!mounted) return;
    setState(() {
      _children = children;
      _loading = false;
    });
  }

  void _enter(String folder) => _load(_rel.isEmpty ? folder : '$_rel/$folder');

  /// Navigate to the prefix containing [depth] segments; zero selects the root.
  void _goToDepth(int depth) => _load(_segments.take(depth).join('/'));

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final atRoot = _rel.isEmpty;

    return AlertDialog(
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Where to work?',
            style: context.typo.title.copyWith(
              fontSize: 15,
              color: colors.text,
            ),
          ),
          const SizedBox(height: 8),
          _Breadcrumb(
            projectName: widget.projectName,
            segments: _segments,
            onTapSegment: _goToDepth,
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Divider(height: 1, color: colors.border),
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: CircularProgressIndicator(size: 20)),
                    )
                  : ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      children: [
                        // ".." moves up one level and is hidden at the root.
                        if (!atRoot)
                          _FolderRow(
                            icon: Icons.arrow_upward,
                            label: '..',
                            onTap: () => _goToDepth(_segments.length - 1),
                          ),
                        for (final folder in _children)
                          _FolderRow(
                            icon: Icons.folder_outlined,
                            label: folder,
                            trailing: Icons.chevron_right,
                            onTap: () => _enter(folder),
                          ),
                        if (_children.isEmpty && !atRoot)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 14,
                            ),
                            child: Text(
                              'No subfolders here.',
                              style: context.typo.label.copyWith(
                                color: colors.text4,
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
            Divider(height: 1, color: colors.border),
            const SizedBox(height: 10),
            Text(
              atRoot
                  ? 'Use the root of ${widget.projectName}'
                  : 'Use ${widget.projectName}/$_rel',
              overflow: TextOverflow.ellipsis,
              style: context.typo.label.copyWith(color: colors.text3),
            ),
          ],
        ),
      ),
      actions: [
        OutlineButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        PrimaryButton(
          onPressed: () => Navigator.of(context).pop(_rel),
          child: const Text('Use this folder'),
        ),
      ],
    );
  }
}

/// Navigate directly through clickable project path segments.
class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({
    required this.projectName,
    required this.segments,
    required this.onTapSegment,
  });

  final String projectName;
  final List<String> segments;
  final void Function(int depth) onTapSegment;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final crumbs = <Widget>[
      _crumb(context, projectName, 0, isLast: segments.isEmpty),
    ];
    for (var i = 0; i < segments.length; i++) {
      crumbs.add(Icon(Icons.chevron_right, size: 14, color: colors.text4));
      crumbs.add(
        _crumb(context, segments[i], i + 1, isLast: i == segments.length - 1),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(mainAxisSize: MainAxisSize.min, children: crumbs),
    );
  }

  Widget _crumb(
    BuildContext context,
    String label,
    int depth, {
    required bool isLast,
  }) {
    final colors = context.colors;
    final style = context.typo.label.copyWith(
      color: isLast ? colors.text : colors.text3,
      fontWeight: isLast ? FontWeight.w600 : FontWeight.w400,
    );
    if (isLast) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Text(label, style: style),
      );
    }
    return HoverTap(
      onTap: () => onTapSegment(depth),
      borderRadius: const BorderRadius.all(Radius.circular(5)),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Text(label, style: style),
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final IconData? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return HoverTap(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Row(
        children: [
          Icon(icon, size: 16, color: colors.text3),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: context.typo.body.copyWith(
                fontSize: 13.5,
                color: colors.text,
              ),
            ),
          ),
          if (trailing != null) Icon(trailing, size: 16, color: colors.text4),
        ],
      ),
    );
  }
}
