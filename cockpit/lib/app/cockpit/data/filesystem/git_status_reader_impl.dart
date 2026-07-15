import 'dart:io';

import 'package:cockpit/app/cockpit/domain/contracts/git_status_reader.dart';
import 'package:cockpit/app/cockpit/domain/entities/git_file_status.dart';
import 'package:cockpit/app/cockpit/domain/entities/git_info.dart';

/// Read repository status by running a resolved `git` executable.
///
/// Because a macOS app does not inherit the shell PATH, probes known executable
/// locations once and caches the result.
class GitStatusReaderImpl implements GitStatusReader {
  GitStatusReaderImpl();

  String? _git; // Executable path, resolved once.

  static const List<String> _candidates = <String>[
    '/usr/bin/git',
    '/opt/homebrew/bin/git',
    '/usr/local/bin/git',
  ];

  Future<String> _resolveGit() async {
    final cached = _git;
    if (cached != null) return cached;
    for (final candidate in _candidates) {
      if (await File(candidate).exists()) return _git = candidate;
    }
    return _git = 'git'; // Last resort: PATH.
  }

  @override
  Future<GitInfo?> read(String path) async {
    try {
      final git = await _resolveGit();

      // The current-branch lookup also determines whether the path is a Git repo.
      final branchRes = await Process.run(git, [
        '-C',
        path,
        'rev-parse',
        '--abbrev-ref',
        'HEAD',
      ]);
      if (branchRes.exitCode != 0) return null;
      var branch = (branchRes.stdout as String).trim();
      if (branch.isEmpty) return null;
      if (branch == 'HEAD') {
        // Show the short SHA instead of a branch name for detached HEAD.
        final shaRes = await Process.run(git, [
          '-C',
          path,
          'rev-parse',
          '--short',
          'HEAD',
        ]);
        branch = shaRes.exitCode == 0
            ? (shaRes.stdout as String).trim()
            : 'HEAD';
      }

      // Per-file status uses `-z` for NUL-separated entries and unquoted,
      // unescaped paths. `--ignored` adds collapsed `!!` directory entries
      // without recursively scanning them. Renames consume the old path token.
      final statusRes = await Process.run(git, [
        '-C',
        path,
        'status',
        '--porcelain=v1',
        '-z',
        '--ignored',
      ]);
      final (files, ignored, untrackedDirs) = statusRes.exitCode == 0
          ? _parsePorcelainZ(statusRes.stdout as String)
          : (
              const <String, GitFileStatus>{},
              const <String>{},
              const <String>{},
            );

      // Compare with the upstream without fetching, so values reflect the last
      // known refs. `--count A...B` with `@{upstream}...HEAD` returns
      // "<behind>\t<ahead>"; no configured upstream leaves both values at zero.
      var ahead = 0;
      var behind = 0;
      final abRes = await Process.run(git, [
        '-C',
        path,
        'rev-list',
        '--left-right',
        '--count',
        '@{upstream}...HEAD',
      ]);
      if (abRes.exitCode == 0) {
        final parts = (abRes.stdout as String).trim().split(RegExp(r'\s+'));
        if (parts.length == 2) {
          behind = int.tryParse(parts[0]) ?? 0;
          ahead = int.tryParse(parts[1]) ?? 0;
        }
      }

      return GitInfo(
        branch: branch,
        ahead: ahead,
        behind: behind,
        files: files,
        ignored: ignored,
        untrackedDirs: untrackedDirs,
      );
    } catch (_) {
      return null; // Git is unavailable or the directory cannot be accessed.
    }
  }

  /// Parse `git status --porcelain=v1 -z` into status and collapsed-root sets.
  ///
  /// Each entry is NUL-terminated `XY <path>`. Index renames and copies (`R` or
  /// `C`) include an extra old-path token, which is skipped. Git collapses
  /// wholly new or ignored directories into one trailing-slash entry (`?? dir/`
  /// or `!! dir/`), so their roots are retained to classify descendants that
  /// Git does not enumerate.
  static (Map<String, GitFileStatus>, Set<String>, Set<String>)
  _parsePorcelainZ(String raw) {
    final out = <String, GitFileStatus>{};
    final ignored = <String>{};
    final untrackedDirs = <String>{};
    final tokens = raw.split('\u0000');
    for (var i = 0; i < tokens.length; i++) {
      final entry = tokens[i];
      if (entry.length < 4) continue; // Skip the final empty token.
      final x = entry[0];
      final y = entry[1];
      var pathPart = entry.substring(3); // Skip "XY ".
      // An index rename/copy uses the next NUL token for the old path; skip it.
      if (x == 'R' || x == 'C') i++;
      final isDir = pathPart.endsWith('/'); // Collapsed `??` or `!!` directory.
      if (isDir) pathPart = pathPart.substring(0, pathPart.length - 1);
      if (pathPart.isEmpty) continue;
      if (x == '!' && y == '!') {
        ignored.add(pathPart); // Ignored root covers descendants.
        continue;
      }
      if (x == '?' && y == '?' && isDir) {
        untrackedDirs.add(
          pathPart,
        ); // Collapsed new directory covers descendants.
      }
      final status = _classify(x, y);
      if (status != null) out[pathPart] = status;
    }
    return (out, ignored, untrackedDirs);
  }

  /// Map porcelain status characters to the display classification.
  ///
  /// Working-tree changes (`Y`) take display precedence over index changes
  /// (`X`), except for conflicts and deletions. Returns `null` for `!!` and
  /// states that do not need coloring.
  static GitFileStatus? _classify(String x, String y) {
    // Untracked.
    if (x == '?' && y == '?') return GitFileStatus.untracked;
    // Ignored; present only with --ignored, checked defensively.
    if (x == '!' && y == '!') return null;
    // Conflict: either side is 'U', or both sides added/deleted.
    if (x == 'U' ||
        y == 'U' ||
        (x == 'D' && y == 'D') ||
        (x == 'A' && y == 'A')) {
      return GitFileStatus.conflict;
    }
    // Deleted in either the index or working tree.
    if (x == 'D' || y == 'D') return GitFileStatus.deleted;
    // An unstaged working-tree change is modified.
    if (y == 'M' || y == 'T' || y == 'R' || y == 'C') {
      return GitFileStatus.modified;
    }
    // An index-only change is staged, including an add (`A`).
    if (x == 'M' || x == 'T' || x == 'R' || x == 'C' || x == 'A') {
      return GitFileStatus.staged;
    }
    return null;
  }
}
