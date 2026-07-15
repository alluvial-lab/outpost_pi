/// Identify why worktree-name validation failed so the dialog can show the
/// correct cause as the user types (plan/42, decisions 10 and 11).
enum WorktreeNameError {
  /// No name has been entered yet.
  empty,

  /// Contains a space or another whitespace character forbidden by policy.
  whitespace,

  /// Contains a character Git rejects: `~`, `^`, `:`, `?`, `*`, `[`, `\\`,
  /// or a control character.
  invalidChar,

  /// Is only `@`, starts or ends with `/`, or contains `..`, `@{`, or `//`.
  invalidSequence,

  /// Starts with `-` or `.`, ends with `.` or `.lock`, or has a path component
  /// that starts with `.` or ends with `.lock`.
  reserved,

  /// Conflicts with an existing local branch.
  duplicateBranch,

  /// Conflicts with an existing worktree name.
  duplicateWorktree,
}

/// Represent the accepted or rejected result of validating a worktree name.
class WorktreeNameCheck {
  /// Create an accepted validation result.
  const WorktreeNameCheck.valid() : error = null;

  /// Create a rejected validation result with its precise [error].
  const WorktreeNameCheck.invalid(this.error);

  /// The rejection cause, or `null` when the name is valid.
  final WorktreeNameError? error;

  /// Report whether validation accepted the name.
  bool get isValid => error == null;
}

/// Validate a worktree name as a new Git branch without performing I/O.
///
/// This pure-Dart implementation provides immediate dialog feedback without a
/// Git binary. It faithfully covers the documented subset of
/// `git check-ref-format --branch` required by the product; the real
/// `git worktree add` remains the final gate.
///
/// Uniqueness is checked against the supplied local branches and worktree
/// names, which callers collect once when opening the dialog (decision 11).
class WorktreeNameValidator {
  /// Create a stateless worktree-name validator.
  const WorktreeNameValidator();

  static const Set<String> _forbiddenChars = <String>{
    ' ', '\t', '\n', '\r', // Whitespace is handled first; retained defensively.
    '~', '^', ':', '?', '*', '[', r'\',
  };

  /// Validate [name] with format errors taking precedence over duplicates.
  ///
  /// Duplicate checks use [existingBranches] and [existingWorktreeNames]
  /// exactly as supplied; this method performs no filesystem or Git queries.
  WorktreeNameCheck validate(
    String name, {
    required Set<String> existingBranches,
    required Set<String> existingWorktreeNames,
  }) {
    if (name.isEmpty) {
      return const WorktreeNameCheck.invalid(WorktreeNameError.empty);
    }

    // 1. Whitespace has its own user-facing failure and highest precedence.
    for (final unit in name.codeUnits) {
      if (unit == 0x20 || unit == 0x09 || unit == 0x0a || unit == 0x0d) {
        return const WorktreeNameCheck.invalid(WorktreeNameError.whitespace);
      }
    }

    // 2. Reject forbidden characters, control characters, and DEL (0x7f).
    for (final unit in name.codeUnits) {
      if (unit < 0x20 || unit == 0x7f) {
        return const WorktreeNameCheck.invalid(WorktreeNameError.invalidChar);
      }
    }
    for (final ch in _forbiddenChars) {
      if (name.contains(ch)) {
        return const WorktreeNameCheck.invalid(WorktreeNameError.invalidChar);
      }
    }

    // 3. Reject invalid sequences and slash positions.
    if (name == '@' ||
        name.contains('..') ||
        name.contains('@{') ||
        name.contains('//') ||
        name.startsWith('/') ||
        name.endsWith('/')) {
      return const WorktreeNameCheck.invalid(WorktreeNameError.invalidSequence);
    }

    // 4. Reject reserved positions globally and within each path component.
    if (name.startsWith('-') || name.endsWith('.') || name.endsWith('.lock')) {
      return const WorktreeNameCheck.invalid(WorktreeNameError.reserved);
    }
    for (final part in name.split('/')) {
      if (part.startsWith('.') || part.endsWith('.lock')) {
        return const WorktreeNameCheck.invalid(WorktreeNameError.reserved);
      }
    }

    // 5. Enforce uniqueness across local branches and existing worktrees.
    if (existingBranches.contains(name)) {
      return const WorktreeNameCheck.invalid(WorktreeNameError.duplicateBranch);
    }
    if (existingWorktreeNames.contains(name)) {
      return const WorktreeNameCheck.invalid(
        WorktreeNameError.duplicateWorktree,
      );
    }

    return const WorktreeNameCheck.valid();
  }
}
