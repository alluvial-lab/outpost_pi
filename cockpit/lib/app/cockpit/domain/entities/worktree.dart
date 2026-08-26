/// Represent a workspace's Git worktree shown as a fork beneath it in the rail.
///
/// It is rendered at runtime as a child [Project] with `parentId`, but Git
/// (`git worktree list`) is the source of truth for its existence rather than
/// local state. See `plan/42-cockpit-worktrees.md` decisions 1, 4, and 5.
class Worktree {
  const Worktree({
    required this.path,
    required this.branch,
    required this.isDetached,
  });

  /// Absolute path to the worktree checkout.
  final String path;

  /// Worktree branch name, or the short SHA when [isDetached].
  final String branch;

  /// Whether the worktree has a detached HEAD and no branch.
  ///
  /// This preserves externally created worktrees in the faithful Git mirror
  /// required by decision 5.
  final bool isDetached;

  /// Use path for identity because two worktrees cannot share a directory.
  @override
  bool operator ==(Object other) => other is Worktree && other.path == path;

  @override
  int get hashCode => path.hashCode;
}
