/// Represent a directory saved by the user as a workspace.
///
/// Root workspaces are persisted through the project repository. **Worktrees**
/// are runtime `Project` forks with [parentId], derived from Git and never persisted because
/// Git owns their existence (see `plan/42`, decisions 1 and 4). Cockpit agents
/// operate in subdirectories of [path].
class Project {
  const Project({
    required this.id,
    required this.name,
    required this.path,
    required this.colorValue,
    required this.createdAt,
    this.parentId,
    this.order = 0,
    this.imagePath,
  });

  /// Sentinel allowing [copyWith] to distinguish preserving [imagePath] from
  /// clearing it by passing `null`.
  static const Object unchanged = Object();

  final String id;

  /// Display name, defaulting to the basename of [path].
  final String name;

  /// Absolute path to the project root.
  final String path;

  /// ARGB avatar color assigned when the project is created.
  final int colorValue;

  final DateTime createdAt;

  /// Parent workspace id for a worktree fork, or `null` for a root workspace.
  ///
  /// Defines nesting in the rail.
  final String? parentId;

  /// Manual workspace position in the drag-and-drop rail.
  ///
  /// Only root workspaces use this persisted value; worktrees inherit their
  /// parent's position and nest below it. The default `0` lets legacy data fall
  /// back to [createdAt] ordering.
  final int order;

  /// Absolute path to a persisted PNG or JPG that replaces the initial avatar.
  ///
  /// `null` means no image. If the file is missing or unreadable, the UI uses
  /// the `WorkspaceAvatar` error placeholder.
  final String? imagePath;

  /// Return whether this project is another workspace's worktree.
  bool get isWorktree => parentId != null;

  /// Derive the uppercase initial used by the rail avatar.
  String get initial => name.isNotEmpty ? name[0].toUpperCase() : '?';

  Project copyWith({
    String? name,
    int? colorValue,
    int? order,
    Object? imagePath = unchanged,
  }) => Project(
    id: id,
    name: name ?? this.name,
    path: path,
    colorValue: colorValue ?? this.colorValue,
    createdAt: createdAt,
    parentId: parentId,
    order: order ?? this.order,
    imagePath: imagePath == unchanged ? this.imagePath : imagePath as String?,
  );

  @override
  bool operator ==(Object other) => other is Project && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
