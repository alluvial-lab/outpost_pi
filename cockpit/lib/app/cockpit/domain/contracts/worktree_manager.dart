import 'package:cockpit/app/cockpit/domain/entities/worktree.dart';
import 'package:cockpit/app/core/domain/result.dart';

/// Carry Git output from a failed worktree operation for inline dialog display
/// under plan 42, decision 21.
class WorktreeOpError {
  const WorktreeOpError(this.message);

  /// Provide a readable message, usually Git's stderr.
  final String message;
}

/// Capture local branches and worktree names already used in a repository.
///
/// Collected once when the creation dialog opens, this namespace supplies the
/// uniqueness validation required by decision 11.
class WorktreeNamespace {
  const WorktreeNamespace({
    required this.branches,
    required this.worktreeNames,
  });

  const WorktreeNamespace.empty()
    : branches = const <String>{},
      worktreeNames = const <String>{};

  /// Contain local branch names from `git branch`.
  final Set<String> branches;

  /// Contain existing worktree basenames from `git worktree list`.
  final Set<String> worktreeNames;
}

/// Own Cockpit's **mutable** Git worktree boundary for listing, creating, and
/// removing worktrees.
///
/// This domain contract is implemented in `data/` by running `git worktree …`.
/// Keep read-only branch and dirty-count state in [GitStatusReader] instead.
abstract class WorktreeManager {
  /// List worktrees for [repoPath], **excluding** its workspace root.
  ///
  /// Returns an empty list when [repoPath] is not a Git repository or Git is
  /// unavailable, as required by decisions 4 and 5.
  Future<List<Worktree>> list(String repoPath);

  /// Return local branches and worktree names for uniqueness validation.
  ///
  /// Returns an empty namespace when [repoPath] is not a Git repository or an
  /// error occurs.
  Future<WorktreeNamespace> namespace(String repoPath);

  /// Create `<repoPath>/.pi/remote/worktrees/<name>` on a **new** [name] branch
  /// from the repository's current HEAD, as required by decisions 2, 3, and 15.
  ///
  /// [name] must already have passed name validation. Returns the created
  /// worktree on success and Git output in [WorktreeOpError] on failure.
  Future<Result<Worktree, WorktreeOpError>> add(String repoPath, String name);

  /// Remove the worktree at [worktreePath] and optionally delete [branch].
  ///
  /// When [branch] is not empty, decision 6 requires `git worktree remove`
  /// **before** `git branch -D`. Returns success only after the ordered removal
  /// completes, or [WorktreeOpError] with Git output on failure.
  Future<Result<void, WorktreeOpError>> remove(
    String repoPath,
    String worktreePath,
    String branch,
  );

  /// Report whether [branch] is merged into the repository's main line according
  /// to `git branch --merged`.
  ///
  /// This drives decision 6's unmerged-branch warning before removal. Returns
  /// `false` on uncertainty or error so the warning is shown safely.
  Future<bool> isBranchMerged(String repoPath, String branch);
}
