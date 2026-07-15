/// Represent the Git status of one path or an aggregated directory in the tree.
///
/// Declaration order defines severity precedence from weakest to strongest.
/// Directory aggregation uses [strongest], so the status with the greatest
/// `index` wins. For example, a directory containing untracked and modified
/// files is `modified`; one containing a conflict is `conflict`.
enum GitFileStatus {
  /// Ignored by `.gitignore` (`!!`); any actual change wins aggregation.
  ignored,

  /// New file that is not yet tracked (`??`).
  untracked,

  /// Index change that is staged with no pending working-tree change.
  staged,

  /// Uncommitted working-tree change, including modification or type change.
  modified,

  /// Removal from either the index or the working tree.
  deleted,

  /// Merge conflict where both sides changed the path (`UU`, `AA`, `DD`, etc.).
  conflict;

  /// Return the more severe status by `index`, treating `null` as no status.
  static GitFileStatus? strongest(GitFileStatus? a, GitFileStatus? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.index >= b.index ? a : b;
  }
}
