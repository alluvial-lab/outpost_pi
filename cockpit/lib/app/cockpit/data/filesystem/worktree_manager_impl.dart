import 'dart:io';

import 'package:cockpit/app/cockpit/domain/contracts/worktree_manager.dart';
import 'package:cockpit/app/cockpit/domain/entities/worktree.dart';
import 'package:cockpit/app/core/domain/result.dart';

/// List, create, and remove worktrees through a resolved `git` executable.
///
/// Because a macOS app does not inherit the shell PATH, probes known executable
/// locations once using the same strategy as [GitStatusReaderImpl].
class WorktreeManagerImpl implements WorktreeManager {
  WorktreeManagerImpl();

  String? _git; // Executable path, resolved once.

  static const List<String> _candidates = <String>[
    '/usr/bin/git',
    '/opt/homebrew/bin/git',
    '/usr/local/bin/git',
  ];

  /// Location for Cockpit-created worktrees, relative to the repository root.
  static const String worktreesSubdir = '.pi/remote/worktrees';

  Future<String> _resolveGit() async {
    final cached = _git;
    if (cached != null) return cached;
    for (final candidate in _candidates) {
      if (await File(candidate).exists()) return _git = candidate;
    }
    return _git = 'git'; // Last resort: PATH.
  }

  @override
  Future<List<Worktree>> list(String repoPath) async {
    try {
      final git = await _resolveGit();
      final res = await Process.run(git, [
        '-C',
        repoPath,
        'worktree',
        'list',
        '--porcelain',
      ]);
      if (res.exitCode != 0) return const <Worktree>[];
      return _parsePorcelain(res.stdout as String);
    } catch (_) {
      return const <Worktree>[];
    }
  }

  @override
  Future<WorktreeNamespace> namespace(String repoPath) async {
    try {
      final git = await _resolveGit();
      final branchRes = await Process.run(git, [
        '-C',
        repoPath,
        'branch',
        '--format=%(refname:short)',
      ]);
      if (branchRes.exitCode != 0) return const WorktreeNamespace.empty();
      final branches = (branchRes.stdout as String)
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toSet();
      final worktreeNames = (await list(
        repoPath,
      )).map((w) => _basename(w.path)).toSet();
      return WorktreeNamespace(
        branches: branches,
        worktreeNames: worktreeNames,
      );
    } catch (_) {
      return const WorktreeNamespace.empty();
    }
  }

  @override
  Future<Result<Worktree, WorktreeOpError>> add(
    String repoPath,
    String name,
  ) async {
    try {
      final git = await _resolveGit();
      // Cross-platform rule: create a worktree only when the branch is absent.
      // Otherwise `worktree add -b` fails ("branch already exists") or may leave
      // the repository partially created.
      if (await _branchExists(git, repoPath, name)) {
        return const Failure(
          WorktreeOpError('A branch with that name already exists.'),
        );
      }
      final target = '$repoPath/$worktreesSubdir/$name';
      // Create the branch from the repository's current HEAD without an explicit ref.
      final res = await Process.run(git, [
        '-C',
        repoPath,
        'worktree',
        'add',
        target,
        '-b',
        name,
      ]);
      if (res.exitCode != 0) {
        return Failure(WorktreeOpError(_errText(res)));
      }
      // Return the path exactly as Git lists it, with native OS separators,
      // rather than the `/`-joined `target`. On Windows, Git lists `\`; returning
      // `target` would not match `list()`, so the new fork would appear missing
      // and the dialog would remain open.
      final created = (await list(repoPath)).where((w) => w.branch == name);
      return Success(
        created.isNotEmpty
            ? created.first
            : Worktree(path: target, branch: name, isDetached: false),
      );
    } catch (e) {
      return Failure(WorktreeOpError('Failed to create worktree: $e'));
    }
  }

  /// Check whether the local branch [name] already exists in the repository.
  Future<bool> _branchExists(String git, String repoPath, String name) async {
    final res = await Process.run(git, [
      '-C',
      repoPath,
      'show-ref',
      '--verify',
      '--quiet',
      'refs/heads/$name',
    ]);
    return res.exitCode == 0;
  }

  @override
  Future<Result<void, WorktreeOpError>> remove(
    String repoPath,
    String worktreePath,
    String branch,
  ) async {
    try {
      final git = await _resolveGit();
      // 1. Remove the worktree first. The user already confirmed `--force`,
      //    including removal with a dirty working tree.
      final rmRes = await Process.run(git, [
        '-C',
        repoPath,
        'worktree',
        'remove',
        '--force',
        worktreePath,
      ]);
      if (rmRes.exitCode != 0) {
        return Failure(WorktreeOpError(_errText(rmRes)));
      }
      // 2. Then delete the branch; Git rejects deleting one used by a worktree.
      if (branch.isNotEmpty) {
        final brRes = await Process.run(git, [
          '-C',
          repoPath,
          'branch',
          '-D',
          branch,
        ]);
        if (brRes.exitCode != 0) {
          return Failure(WorktreeOpError(_errText(brRes)));
        }
      }
      return const Success(null);
    } catch (e) {
      return Failure(WorktreeOpError('Failed to remove worktree: $e'));
    }
  }

  @override
  Future<bool> isBranchMerged(String repoPath, String branch) async {
    if (branch.isEmpty) return false;
    try {
      final git = await _resolveGit();
      // List branches merged into the main checkout's HEAD. If the fork branch
      // appears, it is merged; uncertainty or errors return false for a warning.
      //
      // `--merged` accepts an optional `<commit>` and would consume a following
      // `--format` as that object ("malformed object name"), so parse the plain
      // output and strip its line marker (`* ` current, `+ ` worktree, or `  `).
      final res = await Process.run(git, [
        '-C',
        repoPath,
        'branch',
        '--merged',
      ]);
      if (res.exitCode != 0) return false;
      final merged = (res.stdout as String)
          .split('\n')
          .map((l) => l.replaceFirst(RegExp(r'^[*+]?\s+'), '').trim())
          .where((l) => l.isNotEmpty)
          .toSet();
      return merged.contains(branch);
    } catch (_) {
      return false;
    }
  }

  /// Parse `git worktree list --porcelain`, discarding the main workspace entry.
  List<Worktree> _parsePorcelain(String out) {
    final blocks = out.split('\n\n');
    final result = <Worktree>[];
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i].trim();
      if (block.isEmpty) continue;
      String? path;
      String? head;
      String? branch;
      var detached = false;
      var bare = false;
      for (final line in block.split('\n')) {
        if (line.startsWith('worktree ')) {
          path = line.substring('worktree '.length).trim();
        } else if (line.startsWith('HEAD ')) {
          head = line.substring('HEAD '.length).trim();
        } else if (line.startsWith('branch ')) {
          final ref = line.substring('branch '.length).trim();
          branch = ref.startsWith('refs/heads/')
              ? ref.substring('refs/heads/'.length)
              : ref;
        } else if (line == 'detached') {
          detached = true;
        } else if (line == 'bare') {
          bare = true;
        }
      }
      // Exclude the first, main entry and bare repositories from forks.
      if (i == 0 || bare || path == null) continue;
      result.add(
        Worktree(
          path: path,
          branch: detached
              ? (head != null && head.length >= 7
                    ? head.substring(0, 7)
                    : 'HEAD')
              : (branch ?? 'HEAD'),
          isDetached: detached,
        ),
      );
    }
    return result;
  }

  String _basename(String path) {
    // Accept `/` on POSIX and the `\` separator emitted by Git on Windows.
    var p = path;
    while ((p.endsWith('/') || p.endsWith(r'\')) && p.length > 1) {
      p = p.substring(0, p.length - 1);
    }
    final idx = p.lastIndexOf(RegExp(r'[/\\]'));
    return idx >= 0 ? p.substring(idx + 1) : p;
  }

  String _errText(ProcessResult res) {
    final err = (res.stderr as String).trim();
    if (err.isNotEmpty) return err;
    final out = (res.stdout as String).trim();
    return out.isNotEmpty ? out : 'git exited with code ${res.exitCode}';
  }
}
