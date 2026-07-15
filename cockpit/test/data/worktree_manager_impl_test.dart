import 'dart:io';

import 'package:cockpit/app/cockpit/data/filesystem/worktree_manager_impl.dart';
import 'package:cockpit/app/cockpit/domain/contracts/worktree_manager.dart';
import 'package:cockpit/app/cockpit/domain/entities/worktree.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final manager = WorktreeManagerImpl();
  late Directory repo;
  late String mainBranch;

  Future<ProcessResult> git(List<String> args, {String? cwd}) =>
      Process.run('git', args, workingDirectory: cwd ?? repo.path);

  Future<bool> gitAvailable() async {
    try {
      return (await Process.run('git', ['--version'])).exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  setUp(() async {
    repo = await Directory.systemTemp.createTemp('cockpit_wt_test_');
    await git(['init']);
    await git(['config', 'user.email', 'test@example.com']);
    await git(['config', 'user.name', 'Test']);
    await File('${repo.path}/README.md').writeAsString('hello');
    await git(['add', '.']);
    await git(['commit', '-m', 'init']);
    mainBranch = (await git([
      'rev-parse',
      '--abbrev-ref',
      'HEAD',
    ])).stdout.toString().trim();
  });

  tearDown(() async {
    if (await repo.exists()) await repo.delete(recursive: true);
  });

  test('add → list → namespace → remove (complete cycle)', () async {
    if (!await gitAvailable()) {
      markTestSkipped('git is unavailable in this environment');
      return;
    }

    // add: create a nested worktree and a new branch from HEAD.
    final added = await manager.add(repo.path, 'feat/sso');
    expect(
      added.isSuccess,
      isTrue,
      reason: added.fold((_) => '', (e) => e.message),
    );
    final wt = (added as Success<Worktree, WorktreeOpError>).value;
    expect(Directory(wt.path).existsSync(), isTrue);
    expect(wt.path, endsWith('/.pi/remote/worktrees/feat/sso'));
    expect(wt.branch, 'feat/sso');
    expect(wt.isDetached, isFalse);

    // list: exclude the root and include the new fork.
    final list = await manager.list(repo.path);
    expect(list.length, 1);
    expect(list.single.branch, 'feat/sso');

    // namespace: base branch + worktree branch + worktree basename.
    final ns = await manager.namespace(repo.path);
    expect(ns.branches, containsAll(<String>[mainBranch, 'feat/sso']));
    expect(ns.worktreeNames, contains('sso'));

    // remove: delete both the folder AND branch (decision 6).
    final removed = await manager.remove(repo.path, wt.path, 'feat/sso');
    expect(
      removed.isSuccess,
      isTrue,
      reason: removed.fold((_) => '', (e) => e.message),
    );
    expect(Directory(wt.path).existsSync(), isFalse);
    expect(await manager.list(repo.path), isEmpty);
    expect(
      (await manager.namespace(repo.path)).branches,
      isNot(contains('feat/sso')),
    );
  });

  test('add fails (Failure with message) for an existing branch', () async {
    if (!await gitAvailable()) {
      markTestSkipped('git is unavailable in this environment');
      return;
    }
    final dup = await manager.add(repo.path, mainBranch);
    expect(dup.isFailure, isTrue);
    expect(
      (dup as Failure<Worktree, WorktreeOpError>).error.message,
      isNotEmpty,
    );
  });

  test('list/namespace return empty for a non-Git folder', () async {
    final tmp = await Directory.systemTemp.createTemp('cockpit_nogit_');
    addTearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });
    expect(await manager.list(tmp.path), isEmpty);
    expect((await manager.namespace(tmp.path)).branches, isEmpty);
  });

  test(
    'isBranchMerged: true without new commits, false after a fork commit',
    () async {
      if (!await gitAvailable()) {
        markTestSkipped('git is unavailable in this environment');
        return;
      }
      final added = await manager.add(repo.path, 'feat/x');
      final wt = (added as Success<Worktree, WorktreeOpError>).value;

      // Just created from HEAD with no commits → merged (tip reachable from HEAD).
      expect(await manager.isBranchMerged(repo.path, 'feat/x'), isTrue);

      // New worktree commit → the tip is no longer reachable from the main HEAD.
      await File('${wt.path}/new.txt').writeAsString('x');
      await git(['add', '.'], cwd: wt.path);
      await git(['commit', '-m', 'work'], cwd: wt.path);
      expect(await manager.isBranchMerged(repo.path, 'feat/x'), isFalse);

      // Empty / nonexistent branch → false (shows the warning for safety).
      expect(await manager.isBranchMerged(repo.path, ''), isFalse);
      expect(await manager.isBranchMerged(repo.path, 'does-not/exist'), isFalse);
    },
  );
}
