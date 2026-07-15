import 'package:cockpit/app/cockpit/domain/entities/git_file_status.dart';

/// Capture a workspace's Git branch, upstream divergence, and dirty paths.
class GitInfo {
  const GitInfo({
    required this.branch,
    this.ahead = 0,
    this.behind = 0,
    this.files = const <String, GitFileStatus>{},
    this.ignored = const <String>{},
    this.untrackedDirs = const <String>{},
  });

  /// Current branch, or the short SHA in detached HEAD state.
  final String branch;

  /// Commits **ahead** of the upstream that need pushing; zero without an upstream.
  final int ahead;

  /// Commits **behind** the upstream that need pulling; zero without an upstream.
  ///
  /// Reflects the latest known `fetch`; Cockpit does not fetch automatically.
  final int behind;

  /// Status of each dirty file, keyed by project-relative `/`-separated paths.
  ///
  /// An empty map denotes a clean tree.
  final Map<String, GitFileStatus> files;

  /// Project-relative `.gitignore` roots without trailing slashes.
  ///
  /// Git collapses ignored directories, so one path covers all descendants.
  /// These paths do not count as dirty and only dim the file tree.
  final Set<String> ignored;

  /// Roots of **collapsed untracked directories** reported by Git.
  ///
  /// A wholly new directory becomes one `?? dir/` entry without enumerated
  /// children. Storing the root without a trailing slash marks every descendant
  /// as untracked.
  final Set<String> untrackedDirs;

  /// Return whether project-relative `/`-separated [rel] is under an ignored root.
  bool isIgnored(String rel) => _under(ignored, rel);

  /// Return whether [rel] is under a collapsed untracked directory.
  bool isUntracked(String rel) => _under(untrackedDirs, rel);

  static bool _under(Set<String> roots, String rel) {
    if (roots.isEmpty) return false;
    if (roots.contains(rel)) return true;
    for (final root in roots) {
      if (rel.startsWith('$root/')) return true;
    }
    return false;
  }

  /// Number of changed files; zero denotes a clean tree.
  int get dirtyCount => files.length;

  bool get isDirty => files.isNotEmpty;

  /// Return whether local and upstream commit positions differ.
  bool get hasUpstreamDiff => ahead > 0 || behind > 0;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GitInfo &&
        other.branch == branch &&
        other.ahead == ahead &&
        other.behind == behind &&
        _sameFiles(other.files, files) &&
        other.ignored.length == ignored.length &&
        other.ignored.containsAll(ignored) &&
        other.untrackedDirs.length == untrackedDirs.length &&
        other.untrackedDirs.containsAll(untrackedDirs);
  }

  @override
  int get hashCode => Object.hash(
    branch,
    ahead,
    behind,
    files.length,
    ignored.length,
    untrackedDirs.length,
  );

  static bool _sameFiles(
    Map<String, GitFileStatus> a,
    Map<String, GitFileStatus> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}
