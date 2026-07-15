import 'dart:io';

import 'package:cockpit/app/cockpit/data/filesystem/git_status_reader_impl.dart';
import 'package:cockpit/app/cockpit/domain/entities/git_file_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final reader = GitStatusReaderImpl();
  late Directory repo;

  Future<ProcessResult> git(List<String> args, {String? cwd}) =>
      Process.run('git', args, workingDirectory: cwd ?? repo.path);

  Future<bool> gitAvailable() async {
    try {
      return (await Process.run('git', ['--version'])).exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<void> write(String rel, String content) =>
      File('${repo.path}/$rel').writeAsString(content);

  setUp(() async {
    repo = await Directory.systemTemp.createTemp('cockpit_git_test_');
    await git(['init']);
    await git(['config', 'user.email', 'test@example.com']);
    await git(['config', 'user.name', 'Test']);
    await write('README.md', 'hello');
    await Directory('${repo.path}/lib').create();
    await write('lib/app.dart', 'void main() {}');
    await git(['add', '.']);
    await git(['commit', '-m', 'init']);
  });

  tearDown(() async {
    if (await repo.exists()) await repo.delete(recursive: true);
  });

  test('non-Git folder → null', () async {
    if (!await gitAvailable()) {
      markTestSkipped('git is unavailable');
      return;
    }
    final plain = await Directory.systemTemp.createTemp('cockpit_plain_');
    addTearDown(() => plain.delete(recursive: true));
    expect(await reader.read(plain.path), isNull);
  });

  test('clean tree → branch with no dirty files', () async {
    if (!await gitAvailable()) {
      markTestSkipped('git is unavailable');
      return;
    }
    final info = await reader.read(repo.path);
    expect(info, isNotNull);
    expect(info!.isDirty, isFalse);
    expect(info.files, isEmpty);
    expect(info.ahead, 0);
    expect(info.behind, 0);
  });

  test('classifies modified / staged / untracked / deleted', () async {
    if (!await gitAvailable()) {
      markTestSkipped('git is unavailable');
      return;
    }
    // Modified working tree (not staged).
    await write('README.md', 'changed');
    // Staged: new file added to the index.
    await write('staged.txt', 'new');
    await git(['add', 'staged.txt']);
    // Untracked: new file outside the index.
    await write('lib/fresh.dart', '// new');
    // Deleted: tracked file removed from disk.
    await File('${repo.path}/lib/app.dart').delete();

    final info = await reader.read(repo.path);
    expect(info, isNotNull);
    final files = info!.files;
    expect(files['README.md'], GitFileStatus.modified);
    expect(files['staged.txt'], GitFileStatus.staged);
    expect(files['lib/fresh.dart'], GitFileStatus.untracked);
    expect(files['lib/app.dart'], GitFileStatus.deleted);
    expect(info.dirtyCount, files.length);
  });

  test('paths with spaces are parsed (-z uses a NUL separator)', () async {
    if (!await gitAvailable()) {
      markTestSkipped('git is unavailable');
      return;
    }
    await write('a file.txt', 'x');
    final info = await reader.read(repo.path);
    expect(info!.files['a file.txt'], GitFileStatus.untracked);
  });

  test('collapsed new (untracked) folder → covers descendants', () async {
    if (!await gitAvailable()) {
      markTestSkipped('git is unavailable');
      return;
    }
    // A completely new directory → Git collapses it into "?? new/".
    await Directory('${repo.path}/new/sub').create(recursive: true);
    await write('new/a.txt', '1');
    await write('new/sub/b.txt', '2');

    final info = await reader.read(repo.path);
    expect(info, isNotNull);
    expect(info!.untrackedDirs, contains('new'));
    // The collapsed folder itself is untracked (colors its row and ancestors).
    expect(info.files['new'], GitFileStatus.untracked);
    // Descendants are not enumerated, but isUntracked still covers them.
    expect(info.isUntracked('new/a.txt'), isTrue);
    expect(info.isUntracked('new/sub/b.txt'), isTrue);
    expect(info.isUntracked('lib/app.dart'), isFalse);
  });

  test('collects ignored roots (.gitignore) without marking dirty', () async {
    if (!await gitAvailable()) {
      markTestSkipped('git is unavailable');
      return;
    }
    await write('.gitignore', 'build/\n*.log\n');
    await git(['add', '.gitignore']);
    await git(['commit', '-m', 'gitignore']);
    await Directory('${repo.path}/build').create();
    await write('build/out.bin', 'x');
    await write('debug.log', 'noise');

    final info = await reader.read(repo.path);
    expect(info, isNotNull);
    // Collapsed folder → 'build' (no slash); standalone file → 'debug.log'.
    expect(info!.ignored, containsAll(<String>{'build', 'debug.log'}));
    // Ignored paths are excluded from files and do not mark the tree dirty.
    expect(info.files.containsKey('build/out.bin'), isFalse);
    expect(info.isDirty, isFalse);
    // Coverage beneath the collapsed root.
    expect(info.isIgnored('build/out.bin'), isTrue);
    expect(info.isIgnored('debug.log'), isTrue);
    expect(info.isIgnored('lib/app.dart'), isFalse);
  });

  test('ahead/behind vs local upstream', () async {
    if (!await gitAvailable()) {
      markTestSkipped('git is unavailable');
      return;
    }
    // Create a "remote" as a bare clone and configure the upstream.
    final bare = await Directory.systemTemp.createTemp('cockpit_bare_');
    addTearDown(() => bare.delete(recursive: true));
    await git(['clone', '--bare', repo.path, bare.path]);
    await git(['remote', 'add', 'origin', bare.path]);
    final branch = (await git([
      'rev-parse',
      '--abbrev-ref',
      'HEAD',
    ])).stdout.toString().trim();
    await git(['push', '-u', 'origin', branch]);

    // One unpushed local commit → ahead 1, behind 0.
    await write('ahead.txt', '1');
    await git(['add', '.']);
    await git(['commit', '-m', 'ahead']);

    final info = await reader.read(repo.path);
    expect(info!.ahead, 1);
    expect(info.behind, 0);
  });
}
